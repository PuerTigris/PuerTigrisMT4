// PuellaTigrisVTSQL_002 →　PuellaTigrisVTSQL_003：ステージ0とそれ以外の場合のVT_BatchMain呼び出し前処理が重複していた。VT_BatchMain内に一本化



// pricetableのキー項目　  ：   ×  ,    ×     , symbol,    ×  , timeframe（価格を取得する時間軸）         ,    ×    , dt（価格の発生時間）    ←　価格は、stageID, strategyIDの影響を受けない。
// indextable のキー項目   ：   ×  ,    ×     , symbol,    ×  , timeframe(移動平均など計算に使った時間軸）,    ×    , calc_dt（計算基準時間） ←　指標は、stageID, strategyIDの影響を受けない。
// vtradetableのキー項目   ：stageID, strategyID, symbol,  ticket, timeframe(約定発生時の時間軸）            , orderType
// vAnalyzedIndexのキー項目：stageID, strategyID, symbol,    ×  , timeframe(指標計算に使った時間軸）        , orderType, PLFlag, analyzeTime, analyzeTime_str



// 【今後の検討事項】
// DB_create_Stoc_vOrdersBUY_PROFITなど4種の平均、偏差を計算する際、基準時間に近い約定ほど重みづけしたり、最近の数％件数のみを対象とするなど、工夫する。
// insert_Indexesの他に、DBアクセスを前提としているのに"DB_"という接頭語が無い関数は無いか？

// 【注意】
// 評価損益を計算する際、(評価基準日close - 約定値)　/ global_Digits を計算すると、(1.1391 - 1.1391) / 0.00001が0にならなかった
// →　テーブル無いの各値が小数点5桁でも同様の問題が発生する。
// →　テーブルのデータ型FLOATにしていたために発生した誤差
//   https://qiita.com/rita_cano_bika/items/9649cceec66da5d39389
//   https://dev.mysql.com/doc/refman/5.6/ja/precision-math-decimal-characteristics.html
// →　DECUMAL型にすることで解決した

//+------------------------------------------------------------------+	
//| PuellaTigrisVT(Virtual Trade)                                    |	
//|  Copyright (c) 2016 トラの親 All rights reserved.                   |	
//|                                                                  |
//+------------------------------------------------------------------+	
#property copyright "Copyright (c) 2016 トラの親 All rights reserved."				
#property link      "http://nenshuuha.blog.fc2.com/"			
#property version   "1.00"
//#property strict
//+------------------------------------------------------------------+	
//| ヘッダーファイル読込                                                     |	
//+------------------------------------------------------------------+	
#include <stderror.mqh>	
#include <stdlib.mqh>	
//#include <Tigris_COMMON.mqh>
#include <Tigris_VirtualTrade.mqh>
#include <Puer_STAT.mqh>
#include <MQLMySQL.mqh>
#include <Tigris_DBMSAccess.mqh>

//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	
#define DB_VTRADENUM_MAX 10000


//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
extern int    VT_JUDGEMETHOD = 1;       // 判断パターン番号1：買い（売り）の範囲内の時、trueを返す。
                                        // 判断パターン番号2：買い（売り）の反対売買の範囲外
                                        // 判断パターン番号3：1,2の両立。買い（売り）の範囲内であって、反対売買の範囲外。
extern double VT_POSITIVE_SIGMA = 4.0;  // 売買判断に使う。指標の平均 ± nσ内で売買を許可する時のn。
extern double VT_NEGATIVE_SIGMA = 1.0;  // 売買判断に使う。指標の平均 ± nσ内で売買を拒否する時のn。

extern bool   VT_CREATRE_HIST_DATA = true;
extern int    VT_MAX_STAGE = 3;
extern int    VT_END_SHIFT = 10000;
//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
string global_strategyName = "temp";
int global_stageID = 0;
int global_TickNo = 0;
int global_Period4vTrade = PERIOD_M1;  // 仮想取引登録用の時間軸


int START_SHIFT = 1;    // 計算対象とするシフトの開始位置。
int END_SHIFT   = VT_END_SHIFT ;  // 計算対象とするシフトの終了位置。テスト環境では、最大でも1000まで。それ以前のデータを取得できないため。

string B_P = "BUY_PROFIT";
string B_L = "BUY_LOSS";
string S_P = "SELL_PROFIT";
string S_L = "SELL_LOSS";

datetime tableUpdateSpan = 60; // pricetableの未登録データを追加する時間間隔。それに伴って、indextable, vtradetable, vAnalyzedIndexも更新する。
datetime lastUpdate      = 0;  // 最後にpricetableの未登録データを追加した時刻。

string sqlGetIndexBuyProfit  = ""; // 買い＋利益である仮想取引に紐づくindextableデータを抽出するSQL文
string sqlGetIndexBuyLoss    = ""; // 買い＋損失である仮想取引に紐づくindextableデータを抽出するSQL文
string sqlGetIndexSellProfit = ""; // 売り＋利益である仮想取引に紐づくindextableデータを抽出するSQL文
string sqlGetIndexSellLoss   = ""; // 売り＋損失である仮想取引に紐づくindextableデータを抽出するSQL文

//
// 平均と偏差計算用データを格納するグローバル変数
//
// トレンド分析
// 1 移動平均:MA
double DB_MA_GC_mData[DB_VTRADENUM_MAX];
double DB_MA_DC_mData[DB_VTRADENUM_MAX];
double DB_MA_Slope5_mData[DB_VTRADENUM_MAX];
double DB_MA_Slope25_mData[DB_VTRADENUM_MAX];
double DB_MA_Slope75_mData[DB_VTRADENUM_MAX];
// 2 ボリンジャーバンドBB
double DB_BB_Width_mData[DB_VTRADENUM_MAX];
// 3 一目均衡表:IK
double DB_IK_TEN_mData[DB_VTRADENUM_MAX];
double DB_IK_CHI_mData[DB_VTRADENUM_MAX];
double DB_IK_LEG_mData[DB_VTRADENUM_MAX];
// 4 MACD:MACD
double DB_MACD_GC_mData[DB_VTRADENUM_MAX];
double DB_MACD_DC_mData[DB_VTRADENUM_MAX];
//
// オシレーター分析
// 1 RSI:RSI
double DB_RSI_VAL_mData[DB_VTRADENUM_MAX];
// 2 ストキャスティクス:STOC
double DB_STOC_VAL_mData[DB_VTRADENUM_MAX];
double DB_STOC_GC_mData[DB_VTRADENUM_MAX];
double DB_STOC_DC_mData[DB_VTRADENUM_MAX];
// 4 RCI:RCI
double DB_RCI_VAL_mData[DB_VTRADENUM_MAX];

// トレンド分析
// 1 移動平均:MA
int DB_MA_GC_mDataNum = 0;
int DB_MA_DC_mDataNum = 0;
int DB_MA_Slope5_mDataNum = 0;
int DB_MA_Slope25_mDataNum = 0;
int DB_MA_Slope75_mDataNum = 0;
// 2 ボリンジャーバンドBB
int DB_BB_Width_mDataNum = 0;
// 3 一目均衡表:IK
int DB_IK_TEN_mDataNum = 0;
int DB_IK_CHI_mDataNum = 0;
int DB_IK_LEG_mDataNum = 0;
// 4 MACD:MACD
int DB_MACD_GC_mDataNum = 0;
int DB_MACD_DC_mDataNum = 0;
//
// オシレーター分析
// 1 RSI:RSI
int DB_RSI_VAL_mDataNum = 0;
// 2 ストキャスティクス:STOC
int DB_STOC_VAL_mDataNum = 0;
int DB_STOC_GC_mDataNum = 0;
int DB_STOC_DC_mDataNum = 0;
// 4 RCI:RCI
int DB_RCI_VAL_mDataNum = 0;

// st_vAnalyzedIndex型データをDB書き込みする時のバッファ
// 次の4種類の変数の値が入りうる。
// st_vAnalyzedIndex st_vAnalyzedIndexesBUY_Profit;  // 買いで利益が出た仮想取引を対象とした指標の分析結果。
// st_vAnalyzedIndex st_vAnalyzedIndexesBUY_Loss;    // 買いで損失が出た仮想取引を対象とした指標の分析結果。
// st_vAnalyzedIndex st_vAnalyzedIndexesSELL_Profit; // 売りで利益が出た仮想取引を対象とした指標の分析結果。
// st_vAnalyzedIndex st_vAnalyzedIndexesSELL_Loss;   // 売りで損失が出た仮想取引を対象とした指標の分析結果。
st_vAnalyzedIndex insBuffer_st_vAnalyzedIndex[VTRADENUM_MAX]; 
//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	



//+------------------------------------------------------------------+	
//| 初期処理                                                         |	
//+------------------------------------------------------------------+	
int init() {
//---
 
   //
   //DBに接続する。
   //
   bool flg_connectDB = DB_initial_Connect2DB();
   if (flg_connectDB == false) {
      return -1; 
   }
   // 
   // DB接続処理は、ここまで。
   // 

   
   // 外部パラメータVT_CREATRE_HIST_DATAがtrueの時のみ、全ての過去データの削除と再作成をする。
   if(VT_CREATRE_HIST_DATA == true) {
      bool ret = DB_delete_create_Price_Index_vTrade_vAnIndex(Symbol(), PERIOD_M1, PERIOD_M15);
      if(ret == false) {
         printf( "[%d]テスト　delete_create_vIndex_vTrade_vAnIndex失敗" , __LINE__);   
      }
/*
printf( "[%d]テスト　start()への移行前実験中。add_Price_Index_vTrade_vAnIndex開始" , __LINE__);   
      add_Price_Index_vTrade_vAnIndex(Symbol(),  // 更新する通貨ペア
                                      PERIOD_M1, // price, 新規発注を行う間隔
                                      Time[0]    // 更新基準時間
                                      );
printf( "[%d]テスト　start()への移行前実験中。add_Price_Index_vTrade_vAnIndex終了" , __LINE__);   
*/
                                            
   }

//---
   return(INIT_SUCCEEDED);  
}


//+------------------------------------------------------------------+	
//| メイン処理                                                       |	
//+------------------------------------------------------------------+	
int start()   {
   // DB接続タイムアウトなどで、DB接続が切れる可能性がある。
   // DBに接続されていない場合は、再度接続を試みる。
   // 失敗すれば、以降の処理を行わない。
   if (DB == -1) {
      bool flg_DBconnect = DB_initial_Connect2DB(); 
      if(flg_DBconnect == false || DB == -1) {
         printf( "[%d]エラー DBに未接続のため、処理不能" , __LINE__, Time[0], TimeToStr(Time[0]));
      }
      return -1;
   }


   // 時間間隔tableUpdateSpanごとにpricetableの未登録データを追加する。
   // 追加した時刻のシフト番号におけるindextableを更新する。
   // 全てのvtradetable及びvAnalyzedIndexを削除し、追加したpricetable及びindextableに基づいて、再作成する。

   if(Time[0] - lastUpdate > tableUpdateSpan * 60) {  
printf( "[%d]テスト 基準時間%d=%sでstart()開始 lastUpdate=%d=%s  > %d" , __LINE__, 
        Time[0], TimeToStr(Time[0]), lastUpdate, TimeToStr(lastUpdate), tableUpdateSpan * 60);
   
      add_Price_Index_vTrade_vAnIndex(Symbol(),  // 更新する通貨ペア
                                      PERIOD_M1, // PERIOD_M1。price, 新規発注を行う間隔
                                      PERIOD_M15,// PERIOD_M15。指標を計算する時に使う時間軸
                                      Time[0]    // 更新基準時間
                                      );

      lastUpdate = Time[0];
   }

   return 1;
}



//+------------------------------------------------------------------+	
//| 終了処理                                                         |	
//+------------------------------------------------------------------+	
int deinit(){	
   //DBとの接続を切断
   MySqlDisconnect(DB);  
   printf( "[%d]テスト　DB接続を終了:%s" , __LINE__, MySqlErrorDescription);      
   
//---
   return(1);  
}
 
//スクリプト開始

// 時間間隔tableUpdateSpanごとにpricetableの未登録データを追加する。
// 追加した時刻のシフト番号におけるindextableを更新する。
// 追加したpricetable及びindextableに基づいて、vtradetable及びvAnalyzedIndexを削除し、再作成する。
// 【参考】
// pricetableのキー項目　  ：   ×  ,    ×     , symbol,    ×  , timeframe（価格を取得する時間軸=M1） ,    ×    , dt（価格の発生時間）    ←　価格は、stageID, strategyIDの影響を受けない。
// indextableのキー項目  　：   ×  ,    ×     , symbol,    ×  , timeframe(指標計算に使った時間軸=M15）,    ×    , calc_dt（計算基準時間） ←　指標は、stageID, strategyIDの影響を受けない。
// vtradetableのキー項目   ：stageID, strategyID, symbol, ticket, timeframe(約定に使った時間軸=M1）     , orderType
// vAnalyzedIndexのキー項目：stageID, strategyID, symbol,    ×  , timeframe(指標計算に使った時間軸=M15）, orderType, PLFlag, analyzeTime, analyzeTime_str
bool add_Price_Index_vTrade_vAnIndex(string   mSymbol,    // 更新する通貨ペア
                                     int      mTimeframe, //　PERIOD_M1。price, 新規発注を行う間隔
                                     int      mTimeframe_calc, // PERIOD_M15。指標を計算する時に使う時間軸
                                     datetime mUpdateTime // 更新基準時間
                           ) {

   // pricetableの追加
   bool flg_AddPrice = DB_add_PriceFromHistoryCentor(mSymbol,     // 通貨ペア名。
                                                  mTimeframe,  // close値を取得する時間間隔。時間軸。PERIOD_M1など。
                                                  mUpdateTime,  // 更新基準時間
                                                  END_SHIFT
                                                  );
   if(flg_AddPrice == false) {
      printf( "[%d]エラー　pricetableにデータ追加失敗:%s:%d:%s" , __LINE__ , 
                           mSymbol, mTimeframe, TimeToStr(mUpdateTime));
      return false;
   }

   // indextableの追加
   bool flg_addIndex = DB_add_Indexes(mSymbol,    // 通貨ペア名。
               mTimeframe,      // PERIOD_M1。計算基準時間を計算するための時間軸。PERIOD_M1なら、1分足のシフトを計算基準時間として、指標を計算する。
               mTimeframe_calc, // PERIOD_M15。指標を計算する時に使う時間軸
               mUpdateTime      // 追加対象とする指標の最終時刻。最新時刻は、登録済みデータやENDSHIFTから計算する。
               );
   if(flg_addIndex == false) {
      printf( "[%d]エラー　indextableにデータ追加失敗:%s:%d:%s" , __LINE__ , 
                           mSymbol, mTimeframe, TimeToStr(mUpdateTime));
      return false;
   }
   

   // vtradetableの再計算
   // vAnalyzedIndexの再計算
   // VT_BatchMainの第1引数を0としてステージ0から再計算をする途中で、vtradetable、vAnalyzedIndexを全て削除する。

   for(int ii = 0; ii < VT_MAX_STAGE; ii++) {
printf( "[%d]テスト　【start()】priceとindexの追加処理ステージ%d　開始" , __LINE__ , ii);
      // ステージ1以降（＝ステージ0以外）は、前のステージの取引が無ければ、何もしない。
      if(ii > 0) {
//printf( "[%d]テスト　【start()】前のステージ%dの仮想取引数を検索する" , __LINE__ , ii-1);
         int vTredeNumOfStage_ii = DB_get_vOrdersNum_stage(ii - 1,     // ステージ番号
                                                        global_strategyName,  // 戦略名 
                                                        mSymbol,  // 通貨ペア
                                                        mTimeframe); //　PERIOD_M1。price, index, 新規発注を行う間隔
         if(vTredeNumOfStage_ii <= 0) {
            printf( "[%d]【start()】現在のステージ%d：前のステージ%dの仮想取引が存在しないため、処理を中断" , __LINE__ , ii, ii-1);
            break;
         }
      }



    
      VT_BatchMain(ii,     // ステージ番号
                   global_strategyName,  // 戦略名 
                   mSymbol,  // 通貨ペア
                   mTimeframe,   //　PERIOD_M1。price, index, 新規発注を行う間隔
                   mTimeframe_calc, // PERIOD_M15。指標を計算する時に使う時間軸
                   Time[0] - (mTimeframe*60) * END_SHIFT, 
                   Time[0]); 

      // 最大のチケット番号を更新する。
      DB_update_global_TickNo();

//printf( "[%d]【start()】ステージ%d　終了" , __LINE__ , ii);  
   }


   return true;

}


//+---------------------------------------------------------------------------------------------------+	
//| pricetable, indextable, vtradetable, vAnalyzedIndexテーブルすべてのデータを削除し、作成しなおす。             |
//| 処理対象外であるpricetableテーブルのデータ削除及び再作成はinsert_PriceFromHistoryCentorを用いる。 |
//+---------------------------------------------------------------------------------------------------+	
bool DB_delete_create_Price_Index_vTrade_vAnIndex(string mSymbol,  // 通貨ペア 
                                               int mTimeframe,     //　PERIOD_M1。price, 新規発注を行う間隔
                                               int mTimeframe_calc // PERIOD_M15。指標を計算する時に使う時間軸
                                               ) {
//printf( "[%d]テスト delete_create_Price_Index_vTr()開始==%s  時間軸=%d" , __LINE__, mSymbol, mTimeframe);

     string currPair  = mSymbol;
     int timeframe    = mTimeframe;

//
// データの一括削除
//

   // pricetableのデータを通貨ペアと時間軸をキーとして、全件削除
   DB_delete_price(mSymbol,     // 削除する通貨ペア。長さ0の時は、通貨ペア名を削除条件に加えない。
                mTimeframe,  // priceを取得した時の時間軸。負の時は、削除条件に加えない
                -1,          // 削除対象とするデータのpricetable.dt開始位置
                -1           // 削除対象とするデータのpricetable.dt終了位置            
                 );
                 
   // indextableのデータを通貨ペアと時間軸をキーとして、全件削除
   DB_delete_index(mSymbol,    // 通貨ペア。
                mTimeframe_calc, // indexを計算した時の時間軸
                -1,         // 開始時間。datetime型
                -1          // 終了時間。datetime型
                 ) ;
              
   // vtradetableのデータを通貨ペアと時間軸をキーとして、全件削除
   DB_delete_vTrade(-1,                  // ステージ番号
                 global_strategyName, // 戦略名。仮置き
                 -1,                  // チケット番号
                 mSymbol,             // 仮想取引の通貨ペア。
                 -1,                  // 取引を発生させた時間軸
                 -1                   // 売買区分
                 );   
                 
//printf( "[%d]テスト DB_delete_vAnalyzedIndex()開始" , __LINE__);
   // vAnalyzedIndexのデータを通貨ペアと時間軸をキーとして、全件削除
   DB_delete_vAnalyzedIndex(
                -1,                  // ステージ番号。負の時は、ステージ番号を削除条件に加えない。
                global_strategyName, // 計算根拠とした取引の戦略名。　　　長さ0の時は、戦略名を削除条件に加えない。
                mSymbol,             // 計算根拠とした取引の通貨ペア。長さ0の時は、戦略名を削除条件に加えない。
                mTimeframe_calc,     // PERIOD_M15。指標を計算する時に使う時間軸
                -1,                  // 全ての売買区分。
                vPL_DEFAULT,         // 全ての損益区分を対象とするため、vPROFITでもvLOSSでもない値を設定する。
                -1                   // 全ての平均、偏差計算時の基準時間。
              );   

   //
   // pricetableの登録
   //
   // 通貨ペア、時間軸、タイムフレームをキーとして、シフトSTART_SHIFT～END_SHIFTの、puelladb.pricetableデータをインポートする。
   // 第2引数をPERIOD_M1とすることで、1分足データをインポートする。
   DB_insert_PriceFromHistoryCentor(mSymbol,    // 通貨ペア
                                 mTimeframe,  //　PERIOD_M1。price, index, 新規発注を行う間隔
                                 START_SHIFT,// インポート開始時点のシフト
                                 END_SHIFT   // インポート終了時点のシフト
                                );     // barShiftEnd


   //
   // indextableの登録
   //                                  
   // タイムフレームとシフトを指定して、puelladb.indextableの値を削除し、各datetime時点での指標を計算し、に入れる。
   // 例えば、第3引数PERIOD_M1、第4引数1、第5引数10000とすることで、1分足のシフト1～10000の指標を計算する。
   // 移動平均などの計算は、PERIOD_M15を使う
   DB_insert_Indexes(mSymbol,   // 通貨ペア名。Symbol()の値。
                  mTimeframe, //　PERIOD_M1。price, index, 新規発注を行う間隔
                  mTimeframe_calc,  // PERIOD_M15。指標を計算する時に使う時間軸
                  START_SHIFT,// indexの計算開始時刻
                  END_SHIFT   // indexの計算終了時刻
                 ); 

   //
   // vtradetableの登録
   //                 
   global_Period4vTrade = PERIOD_M1;

   // ステージ0:無条件で取引追加。
   // ステージn (n≧1）:過去日付からシフト１までの開始時間（基準時間という）で、前ステージ(n-1)の仮想取引から計算した指標を使って、新規仮想取引を追加する。
   // ①前ステージ(n-1)の仮想取引に対して、利確損切強制設定
   // ②前ステージ(n-1)の仮想取引に対して、フロアリング設定
   // ③約定日が基準時間以前の前ステージ(n-1)の仮想取引に対して、決済と評価損益計算
   // ④約定日が基準時間以前の前ステージ(n-1)の仮想取引を使って4指標を計算
   // ⑤4指標を使ってステージnの仮想取引を登録
   for(int ii = 0; ii < VT_MAX_STAGE; ii++) {
//printf( "[%d]ステージ%d　開始" , __LINE__ , ii);
      // ステージ1以降は、前のステージで仮想取引が登録されていることを確認する。
      if(ii > 0) {
         int vTredeNumOfStage_ii = DB_get_vOrdersNum_stage(ii - 1,     // ステージ番号
                                                        global_strategyName,  // 戦略名 
                                                        mSymbol,  // 通貨ペア
                                                        mTimeframe);   // 仮想取引を発注しようとする時間軸。1分足の開始時刻で発注を試み
//printf( "[%d]前のステージ%dの仮想取引数は、%d件" , __LINE__ , ii-1, vTredeNumOfStage_ii);
                                                     
         if(vTredeNumOfStage_ii <= 0) {
            printf( "[%d]現在のステージ%d：前のステージ%dの仮想取引が存在しないため、処理を中断" , __LINE__ , ii, ii-1);
            break;
         }
      }

      DB_update_global_TickNo();
 //     stageNo     = ii;       // 追加する仮想取引のステージ番号 = 0。
 //     strategyID  = global_strategyName;  // 追加する仮想取引の戦略名
 //     symbolName  = currPair;// 削除する仮想取引の通貨ペア
//printf( "[%d]ステージ%d　のVT_BatchMain開始　 戦略=%s 通貨=%s 取引時間軸=%d START=%d END=%d" , __LINE__ , ii, global_strategyName,mSymbol, global_Period4vTrade, START_SHIFT, END_SHIFT);  
      VT_BatchMain(ii,     // ステージ番号
                   global_strategyName,  // 戦略名 
                   mSymbol,  // 通貨ペア
                   mTimeframe,      //　PERIOD_M1。price, index, 新規発注を行う間隔
                   mTimeframe_calc, // PERIOD_M15。指標を計算する時に使う時間軸
                   START_SHIFT, 
                   END_SHIFT); 
//printf( "[%d]ステージ%d　終了" , __LINE__ , ii);  
   }



/*
   string strBuf = "select ticket, estimatePL from vtradetable;";
   int intCursor = MySqlCursorOpen(DB, strBuf);
   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, strBuf);              
   }
   else {
   
      int Rows = MySqlCursorRows(intCursor);
printf( "[%d]テスト　評価損益の出力テスト" , __LINE__);   
      int i;
      for (i=0; i<Rows; i++) {
         if (MySqlCursorFetchRow(intCursor)) {
            // カーソルの指す1件を取得する。
            // 
            int    tick = MySqlGetFieldAsInt(intCursor, 0);    // 決済日            → closeTime
            double pl   = MySqlGetFieldAsDouble(intCursor, 1); // 決済日。string型   →  closeTime_str
            printf( "[%d]テスト　評価損益 tick=%d  PL=>%s<" , __LINE__, tick, DoubleToStr(pl, global_Digits));  
         }
      }
   }
   MySqlCursorClose(intCursor);
*/
   return true;
}








 







//
// puelladb.pricetableの各datetime時点での指標を計算し、puelladb.indextableに入れる。
// 指標の計算基準時間はmTimeframe_calcを時間軸とする。
// 指標の計算（例えば、移動平均など）は、mTimeframeを時間軸とする。
bool DB_add_Indexes(string mSymbol,      // 通貨ペア名。Symbol()の値。
                    int mTimeframe,      //　PERIOD_M1。price, index, 新規発注を行う間隔
                    int mTimeframe_calc, // PERIOD_M15。指標を計算する時に使う時間軸
                    datetime mTargetDt   // 追加対象とする指標の最終時刻。最新時刻は、登録済みデータやENDSHIFTから計算する。
                                  ) {
   bool ret = false;

   datetime startDt = -1;
   datetime endDt   = mTargetDt;
   int  max_calc_dt = -1;

   // 引数mSymbolとmTimeframeを使ってindextableを検索し、最大のcalc_dt(=基準時刻)を取得する。
   string Query = "";
   Query = Query + "select max(calc_dt) from indextable ";
   Query = Query + " where symbol = \'" + mSymbol + "\'";
   Query = Query + " and timeframe = "  + IntegerToString(mTimeframe_calc) + " ";
   int intCursor = MySqlCursorOpen(DB, Query);

   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);
      startDt = -1;      
   }
   else {
      int Rows = MySqlCursorRows(intCursor);
      if(Rows > 0) {
         if (MySqlCursorFetchRow(intCursor)) {
            // カーソルの指す1件を取得する。
           max_calc_dt = MySqlGetFieldAsInt(intCursor, 0);
         }
      }
   }
   MySqlCursorClose(intCursor);


   // 最大のcalc_dtが取得できなかった時は、先頭から追加。　　→グローバル変数END_SHIFT×mTimeframe前から引数mTargetDtまでを追加する。
   if(max_calc_dt < 0) {
      startDt = mTargetDt - END_SHIFT * (mTimeframe * 60);
   } 
   // 最大のcalc_dt > mTargetDtの時は、追加不要　　　　　　　→何もしない。
   else if(max_calc_dt > mTargetDt) {
      /*printf( "[%d]テスト　indextableの追加:最新データが%sのため、引数%s以前のデータは登録済み" ,
               __LINE__, 
               TimeToStr(max_calc_dt), 
               TimeToStr(mTargetDt)    );*/

      // 何もしない
      return true;
   }
   // 0 <= 最大のcalc_dt(=発生時刻) < mTargetDtの時は、最大のdtから追加。→最大のcalc_dtから引数mTargetDtまでを追加する。
   else if(max_calc_dt >= 0 && max_calc_dt <= mTargetDt) {
      startDt = max_calc_dt + 1;
   } 

   if(max_calc_dt < 0) {
      /*printf( "[%d]テスト　indextableの追加:登録済みデータの最新日付(datetime型)が>%d<のため、引数%sのデータは登録できない" ,
               __LINE__, 
               max_calc_dt, 
               TimeToStr(mTargetDt)    );*/

      // 何もしない
      return true;
   }

//printf( "[%d]テスト　indextableの追加:%s:時間軸=%d:%sから%sまでを追加" , __LINE__, mSymbol, mTimeframe, TimeToStr(startDt), TimeToStr(endDt));
      // シフトとtimedateは、開始と終了を逆転させる。
      int startDt_SHIFT = iBarShift(mSymbol, mTimeframe, endDt,   false); 
      int endDt_SHIFT   = iBarShift(mSymbol, mTimeframe, startDt, false); 
      ret = DB_insert_Indexes(mSymbol,         // 通貨ペア名。Symbol()の値。
                              mTimeframe,      //　PERIOD_M1。price, index, 新規発注を行う間隔
                              mTimeframe_calc, // PERIOD_M15。指標を計算する時に使う時間軸
                              startDt_SHIFT,   // インポート開始時点のシフト
                              endDt_SHIFT      // インポート終了時点のシフト
                               ) ;



   return ret;
}



//
// puelladb.pricetableの各datetime時点での指標を計算し、puelladb.indextableに入れる。
//

bool DB_insert_Indexes(string mSymbol,      // 通貨ペア名。
                       int mTimeframe,      //　PERIOD_M1。price, index, 新規発注を行う間隔
                       int mTimeframe_calc, // PERIOD_M15。指標を計算する時に使う時間軸
                       int mBarShiftStart,  // 計算開始時点のシフト
                       int mBarShiftEnd     // 計算終了時点のシフト
                                  ) {
                                  
   if(mBarShiftStart >  mBarShiftEnd) {
printf( "[%d]エラー　引数誤りmBarShiftStart(%d) >  mBarShiftEnd(%d)" , __LINE__, mBarShiftStart, mBarShiftEnd);
      return false;
   }
   
   bool errFlag = true;
   
   string bufOpen = "";
   string bufHigh = "";
   string bufLow = "";
   string bufClose = "";
   string bufVolume = "";
   string Query   = "";
                
   if(errFlag == true) { 
      // 追加しようとしているindexデータの削除
      Query = "delete from indextable where " +
              "symbol = \'"  + mSymbol + "\' and " +
              "timeframe = " + IntegerToString(mTimeframe_calc) + " ";              
      // 引数mBarShiftStart(iOpen)及びmBarShiftEnd(iClose)が0以上ならば、delete文の実行対象を絞り込む。
      string postQuery = "";
      datetime dt_start = -1; // delete文の実行対象の開始時間
      datetime dt_end   = -1; // delete文の実行対象の終了時間
      if(mBarShiftStart < 0 && mBarShiftEnd < 0) {
         // mBarShiftStart及びmBarShiftEndが共に負の場合は、calc_dtによる絞り込みはしない。
      }
      else {
         // シフト番号mBarShiftStartが、mBarShiftEndより現在に近い時間 
         if(mBarShiftStart >= 0) {
            dt_start = iTime(mSymbol, mTimeframe, mBarShiftStart);
            if(StringLen(postQuery) > 0) {
               postQuery = postQuery + " and " + "calc_dt <= " + IntegerToString(dt_start) + " ";
            }
            else {
               postQuery = postQuery +           "calc_dt <= " + IntegerToString(dt_start) + " ";
            }
         }  
         else {
            // 引数mBarShiftStartが負の時は、絞り込み条件にしない。
         }
         if(mBarShiftEnd >= 0) {
            dt_end   = iTime(mSymbol, mTimeframe, mBarShiftEnd);
            if(StringLen(postQuery) > 0) {
               postQuery = postQuery + " and " + "calc_dt >= " + IntegerToString(dt_end) + " ";
            }
            else {
               postQuery = postQuery +           "calc_dt >= " + IntegerToString(dt_end) + " ";
            }
         }
      }  // else = mBarShiftStartとmBarShiftEndのどちらかが正。
   
      // postQueryを使った絞り込み追加があれば、Queryに追加する。
      if(StringLen(postQuery) > 0) {
         Query  = Query + " and " + postQuery;
      }

      //データ削除用SQL文を実行
      if (MySqlExecute(DB, Query) == true) {
//         printf( "[%d]テスト　insert_Indexesで削除成功=%s", __LINE__, Query);
     	}
      else {
         printf( "[%d]エラー　Indexes削除失敗:%s" , __LINE__, MySqlErrorDescription);              
         printf( "[%d]エラー　Indexes削除失敗時のSQL:%s" , __LINE__, Query);
         errFlag = false;   
      }   
                
      int barShift = 0;
      bool blFailGetData = false; // 値の取得に失敗したらtrueにする。

      st_vOrderIndex buf_st_vOrderIndexes;  // 計算した指標を格納する構造体。
//printf("[%d]テスト　index計算用の時間軸の確認mTimeframe_calc>%d<←1のはず mTimeframe>%d<", __LINE__, mTimeframe_calc, mTimeframe);

      for(barShift = mBarShiftStart; barShift <= mBarShiftEnd; barShift++) {
         // 指標を計算し、引数st_vOrderIndexesに代入する。
         datetime bufDT = iTime(mSymbol, mTimeframe, barShift);  //←引数mTimeframe（計算基準時間を計算するための時間軸）を使う。
         bool flag_do_calc_Indexes = do_calc_Indexes(mSymbol,         // 入力：通貨ペア
                                                     mTimeframe_calc,        // 入力：指標の計算に使う時間軸。PERIOD_M1, PERIOD_M5など
                                                     bufDT,            // 入力：計算基準時間。datatime型。
                                                     buf_st_vOrderIndexes  // 出力：指標の計算結果。
                                                     );
         // 指標計算関数do_calc_Indexes失敗時。
         if(flag_do_calc_Indexes == false) {
            printf("[%d]テスト　　do_calc_Indexes失敗", __LINE__);
         }
         // 指標計算関数do_calc_Indexes成功時。
         else { 
            Query = "INSERT INTO `indextable` (symbol, timeframe, calc_dt, calc_dt_str, MA_GC, MA_DC, MA_Slope5, MA_Slope25, MA_Slope75, BB_Width, IK_TEN, IK_CHI, IK_LEG, MACD_GC, MACD_DC, RSI_VAL, STOC_VAL, STOC_GC, STOC_DC, RCI_VAL) VALUES (" + 
                     "\'" + mSymbol + "\', " +                        //通貨ペア。文字列
                     IntegerToString(mTimeframe_calc) + ", " +        // PERIOD_M15。指標を計算する時に使う時間軸
                     IntegerToString(bufDT) + ", " +                   //計算基準時間。整数値
                     "\'" +TimeToStr(bufDT) + "\', " +                 //計算基準時間。文字列
                     IntegerToString(buf_st_vOrderIndexes.MA_GC) + ", " +  // MA_GC。整数値
                     IntegerToString(buf_st_vOrderIndexes.MA_DC) + ", " + // MA_DC。整数値
                     DoubleToStr(NormalizeDouble(buf_st_vOrderIndexes.MA_Slope5, global_Digits), global_Digits) + ", " +  // MA_Slope5。double型
                     DoubleToStr(NormalizeDouble(buf_st_vOrderIndexes.MA_Slope25, global_Digits), global_Digits) + ", " + // MA_Slope25。double型
                     DoubleToStr(NormalizeDouble(buf_st_vOrderIndexes.MA_Slope75, global_Digits), global_Digits) + ", " + // MA_Slope75。double型
                     DoubleToStr(NormalizeDouble(buf_st_vOrderIndexes.BB_Width, global_Digits), global_Digits) + ", " +   // BB_Width。double型
                     DoubleToStr(NormalizeDouble(buf_st_vOrderIndexes.IK_TEN, global_Digits), global_Digits) + ", " +     // IK_TEN。double型
                     DoubleToStr(NormalizeDouble(buf_st_vOrderIndexes.IK_CHI, global_Digits), global_Digits) + ", " +     // IK_CHI。double型
                     DoubleToStr(NormalizeDouble(buf_st_vOrderIndexes.IK_LEG, global_Digits), global_Digits) + ", " +     // IK_LEG。double型
                     IntegerToString(buf_st_vOrderIndexes.MACD_GC) + ", " +  // MACD_GC。整数値
                     IntegerToString(buf_st_vOrderIndexes.MACD_DC) + ", " +  // MACD_DC。整数値
                     DoubleToStr(NormalizeDouble(buf_st_vOrderIndexes.RSI_VAL, global_Digits), global_Digits) + ", " +     // RSI_VAL。double型
                     DoubleToStr(NormalizeDouble(buf_st_vOrderIndexes.STOC_VAL, global_Digits), global_Digits) + ", " +    // STOC_VAL。double型
                     IntegerToString(buf_st_vOrderIndexes.STOC_GC) + ", " +  // STOC_GC。整数値
                     IntegerToString(buf_st_vOrderIndexes.STOC_DC) + ", " +  // STOC_DC。整数値
                     DoubleToStr(NormalizeDouble(buf_st_vOrderIndexes.RCI_VAL, global_Digits), global_Digits) +            // RCI_VAL。double型
                    ")";
              
            //SQL文を実行
            if (MySqlExecute(DB, Query) == true) {
//               printf("[%d]テスト　指標計算結果の追加成功:%s", __LINE__, Query);
            }
            else {
               printf( "[%d]エラー　指標計算結果の追加失敗:%s" , __LINE__, MySqlErrorDescription);              
               printf( "[%d]エラー　追加失敗時のSQL:%s" , __LINE__, Query);              
               errFlag = false;
            }
         }     // 指標計算関数do_calc_Indexes成功時。
      }        // for(barShift = barShiftStart; barShift >= barShiftEnd; barShift--) {
   }

   if(errFlag == true) {
      return true;
   }
   else {
      return false;
   }
   
}



//+------------------------------------------------------------------+
//| 仮想取引の一括発注をする　　　                                   |
//+------------------------------------------------------------------+
// VT_BatchMainの変数違い。第5、6引数の開始と終了位置をdatetime型にした。
int VT_BatchMain(int    mStageID,     // ステージ番号
                 string mStrategyID,  // 戦略名 
                 string mSymbol,      // 追加する仮想取引の通貨ペア
                 int    mTimeframe,   //　PERIOD_M1。price, index, 新規発注を行う間隔
                 int    mTimeframe_calc, // PERIOD_M15。指標を計算する時に使う時間軸
                 datetime mStartDt, 
                 datetime mEndDt) {
   int ret = -1;
   if(mStartDt < 0 || mEndDt < 0) {
      return -1;
   }
   


   int startShift = iBarShift(mSymbol, mTimeframe, mStartDt,   false); 
   
   int endShift   = iBarShift(mSymbol, mTimeframe, mEndDt ,   false); 
printf( "[%d]テスト VT_BatchMain内部　mStartDt=%d=%s シフト=%d" , __LINE__, mStartDt, TimeToStr(mStartDt), startShift);
printf( "[%d]テスト VT_BatchMain内部　mEndDt=%d=%s  シフト=%d" , __LINE__, mEndDt, TimeToStr(mEndDt), endShift);
   ret = VT_BatchMain(mStageID,
                      mStrategyID,
                      mSymbol,
                      mTimeframe,
                      mTimeframe_calc,
                      endShift,
                      startShift);
   return ret;
}


int VT_BatchMain(int    mStageID,     // ステージ番号
                 string mStrategyID,  // 戦略名 
                 string mSymbol,      // 追加する仮想取引の通貨ペア
                 int    mTimeframe,   //　PERIOD_M1。price, 新規発注を行う間隔
                 int    mTimeframe_calc, // PERIOD_M15。指標を計算する時に使う時間軸
                 int startShift, 
                 int endShift) {
   int insertedTradeNum = 0;
   int shiftCounter = 0;
   global_stageID   = mStageID; // 仮想取引のテーブル操作時に使う。
   
   datetime mOpenTime = 0;    // 追加する仮想取引の約定時間
   double   mOpenprice = 0.0; // 追加する仮想取引の約定値
   datetime mTargetTime = 0;  // 処理対象となる時間。
   int    stageNo     = -1;      // 削除する仮想取引のステージ番号。すべてを対象とするため、-1。
   int    tickNo      = -1;      // 削除する仮想取引のチケット番号。すべてを対象とするため、-1。
   int    BuySellflag = -1;      // 削除する仮想取引の売買区分。すべてを対象とするため、-1。

   // ステージ0:例外なく、時間軸mTimeFrameのシフトendShift→startShiftの開始時間で仮想取引を追加する。
   if(mStageID == 0) {
      // 全削除。
      // vtradetableテーブルに登録済みのすべての仮想取引を削除する。
      stageNo     = -1;      // 削除する仮想取引のステージ番号。すべてを対象とするため、-1。
      tickNo      = -1;      // 削除する仮想取引のチケット番号。すべてを対象とするため、-1。
      BuySellflag = -1;      // 削除する仮想取引の売買区分。すべてを対象とするため、-1。
      DB_delete_vTrade(-1,          // 全てのステージ番号
                    mStrategyID, // 戦略名。
                    -1,          // 全てのチケット番号
                    mSymbol,     // 仮想取引の通貨ペア。
                    mTimeframe,  //　PERIOD_M1。price, 新規発注を行う間隔
                    -1           // 全ての売買区分
                 );

      // 全削除。
      // vAnalyzedIndexテーブルに登録済みのすべての仮想取引を削除する。
      DB_delete_vAnalyzedIndex(
                   -1,          // ステージ番号。負の時は、ステージ番号を削除条件に加えない。
                   mStrategyID, // 戦略名。　　　長さ0の時は、戦略名を削除条件に加えない。
                   mSymbol,     // 仮想取引の通貨ペア。長さ0の時は、戦略名を削除条件に加えない。
                   mTimeframe_calc,  // PERIOD_M15。指標計算時の時間軸。15分足のデータを使って指標を計算していれば、PERIOD_M15。負の時は、削除条件に加えない。
                   -1,          // 全ての売買区分。
                   vPL_DEFAULT, // 全ての損益区分を対象とするため、vPL_DEFAULTを引数に渡す。
                   -1           // 全ての平均、偏差計算時の基準時間。
                 );
      // ステージ0のため、条件を付けず、仮想取引を追加する。
      for(shiftCounter = endShift; shiftCounter >= 1; shiftCounter--) {
         mOpenTime  =  iTime(mSymbol, mTimeframe, shiftCounter);
         mOpenprice = iClose(mSymbol, mTimeframe, shiftCounter);
         tickNo = DB_v_mOrderSend4(mOpenTime, mSymbol, OP_BUY,  LOTS, mOpenprice, SLIPPAGE, 0.0, 0.0, mStrategyID, 0, 0, LINE_COLOR_LONG);
         // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出すwrite_vOrdersOnMemory(false)は、関数DB_v_mOrderSend4内で行っている。
         if(tickNo <= 0) {
               printf( "[%d]テスト mStageID == 0　買い仮想取引失敗" , __LINE__);
         }
         else {
            insertedTradeNum++;
         }
         tickNo = DB_v_mOrderSend4(mOpenTime, mSymbol, OP_SELL, LOTS, mOpenprice, SLIPPAGE, 0.0, 0.0, mStrategyID, 0, 0, LINE_COLOR_SHORT);
         // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出すwrite_vOrdersOnMemory(false)は、関数DB_v_mOrderSend4内で行っている。
         if(tickNo <= 0) {
            printf( "[%d]テスト mStageID == 0　売り仮想取引失敗" , __LINE__);
         }
         else {
            insertedTradeNum++;
         }
      }

      // 構造体に入った仮想取引をテーブルに出力して、構造体をクリアする。
      write_vOrdersOnMemory(true); // st_vOrders[VTRADENUM_MAX]の利用状況によらず、テーブルに書き出す
      
      //
      // ステージ0の仮想取引は登録するのみとし、指値逆指値設定、FLOORINGTitle、強制決済と評価損益を含む損益計算はしない。
      //　→　ステージ1以降で必要になったタイミングで、随時計算する。
   }
   
   else {  //mStageID > 0の場合
      // ステージn (n≧1）:時間軸mTimeFrameのシフトendShift→startShiftの開始時間で、前ステージ(n-1)の仮想取引から計算した指標を使って、新規仮想取引を追加する。
//printf( "[%d]テスト VT_BatchMain内部　ステージ=%d" , __LINE__, global_stageID);
      if(mStageID == 1) {
         // 
         // ステージn (n≧1）以降を全削除。
         // vtradetableテーブルに登録済みのすべての仮想取引を削除する。
         DB_delete_vTrade(mStageID,    // ステージ番号。mStageID以上の取引データを削除
                       mStrategyID, // 戦略名。
                       -1,          // 全てのチケット番号
                       mSymbol,     // 仮想取引の通貨ペア。
                       mTimeframe,  //　PERIOD_M1。price, 新規発注を行う間隔
                       -1           // 全ての売買区分
                       );

         // ステージn (n≧1）以降を全削除。
         // vAnalyzedIndexテーブルに登録済みのすべての仮想取引を削除する。
         DB_delete_vAnalyzedIndex(
                      mStageID ,   // ステージ番号。ステージ番号mStageID以上のデータをすべて削除。
                      mStrategyID, // 戦略名。　　　長さ0の時は、戦略名を削除条件に加えない。
                      mSymbol,     // 仮想取引の通貨ペア。長さ0の時は、戦略名を削除条件に加えない。
                      mTimeframe_calc, // PERIOD_M15。指標計算時の時間軸。15分足のデータを使って指標を計算していれば、PERIOD_M15。負の時は、削除条件に加えない。
                      -1,          // 全ての売買区分。　　OP_BUY及びOP_SELL以外の時は、削除条件に加えない。
                      vPL_DEFAULT, // 全ての損益区分。vPL_DEFAULTをはじめとしたvPROFIT, vLOSS以外の時は、削除条件に加えない。
                      -1           // 全ての平均、偏差計算時の基準時間。負の時は、削除条件に加えない。
                    );
      }
      // 初期化
      insertedTradeNum = 0;  // 登録する取引の数。
      tickNo = 0;            // チケット番号

      // ステージ1以降のため、前のステージの仮想取引を使った4種平均偏差を使って、仮想取引を追加する。
      for(shiftCounter = endShift; shiftCounter >= startShift; shiftCounter--) {
       
         mTargetTime = iTime(mSymbol, mTimeframe, shiftCounter);
//printf( "[%d]テスト シフト%d 時間=%d--%s" , __LINE__, shiftCounter, mTargetTime, TimeToStr(mTargetTime));


         // ①前ステージ(n-1)の仮想取引に対して、利確損切を当時のASK、BIDによらず、設定する。
         //
         //  TP_PIPSかSL_PIPSのどちらかが0より大きければ、全仮想取引の指値と逆指値をセットする。
         //
         // DB_v_setAllOrdersTPSLは、全仮想取引の指値と逆指値を一律に更新するため、ループの最初（shiftCounter = endShift）にだけ、実行する。
         // 基準時間時点の決済用金額(close)が損切値以上でないと設定できないFLOORING設定とは異なる。
         if(shiftCounter == endShift) {
            if(TP_PIPS > 0 || SL_PIPS > 0) {		
               printf( "[%d]テスト 仮想取引の利確損切設定" , __LINE__);

               DB_v_setAllOrdersTPSL(mStageID - 1,  // ステージn (n≧1）の仮想取引を発注する前提となる1つ前のステージの取引が処理対象
                                     mStrategyID,
                                     mSymbol,
                                     mTimeframe, 
                                     TP_PIPS, 
                                     SL_PIPS);
            } 
         }

         // ②前ステージ(n-1)の仮想取引に対して、フロアリング設定
         //
         // 最小利食値FLOORINGが設定されていれば、損切値の更新を試す
         // 実取引と異なり、「ロングの損切は、その時のBID-ストップレベルより小さくなくてはならない。」という制限はない。
         // 更新により有利な場合にのみ更新する。
         if(FLOORING >= 0) {
            printf( "[%d]テスト FLOORING設定" , __LINE__);
            DB_v_flooringSL(mStageID - 1,         // 処理対象とする仮想取引のステージ番号
                            mStrategyID,
                            mSymbol,
                            mTimeframe,
                            FLOORING);
         }   

         // ③約定日が基準時間以前の前ステージ(n-1)の仮想取引に対して、決済と評価損益計算
         DB_v_doForcedSettlement(mStageID - 1,          // 処理対象とする仮想取引のステージ番号
                                 mStrategyID,
                                 mSymbol,
                                 mTimeframe, 
                                 mTargetTime,   // 決済日。この日時以前の仮想取引に対して、決済する。決済済みの場合は決済損益、それ以外は、評価損益を更新する。
                                 TP_PIPS, 
                                 SL_PIPS);
   
         // ④約定日が基準時間以前の前ステージ(n-1)の仮想取引を使って4指標を計算
         // 最古の仮想取引（テスト中は、最大で1000シフト過去)から現時点(i)のシフト1つ過去（約定日時=i+1)の仮想取引を対象に平均と偏差を計算する。

         // 4指標の格納先であるグローバル変数を初期化する。
         //  - st_vAnalyzedIndex st_vAnalyzedIndexesBUY_Profit;  // 買いで利益が出た仮想取引を対象とした指標の分析結果。
         //  - st_vAnalyzedIndex st_vAnalyzedIndexesBUY_Loss;    // 買いで損失が出た仮想取引を対象とした指標の分析結果。
         //  - st_vAnalyzedIndex st_vAnalyzedIndexesSELL_Profit; // 売りで利益が出た仮想取引を対象とした指標の分析結果。
         //  - st_vAnalyzedIndex st_vAnalyzedIndexesSELL_Loss;   // 売りで損失が出た仮想取引を対象とした指標の分析結果。
         initALL_vMeanSigma();

         // st_vAnalyzedIndexのDB書き込み用バッファを初期化する。 
         init_insBuffer_st_vAnalyzedIndex();
         
         // 4指標の格納先であるグローバル変数に平均と偏差を代入する。
         // 4指標共に計算が行われて、結果は、st_vAnalyzedIndexesBUY_Profitの他、グローバル変数に入る。
         // 4つの計算のうち、4つ全滅失敗したら、falseを返す。
/*
printf( "[%d]テスト ステージ>%d<のシフト>%d::%s<の取引新規追加に向けて、ステージ>%d<のデータを使って4種の平均と偏差を計算" , __LINE__,
mStageID, shiftCounter, TimeToStr(mTargetTime), mStageID - 1);         
*/
         bool flag_getStoc_vOrders = DB_create_st_vAnalyzedIndex(
                                                mStageID - 1,     // 1つ前のステージの取引を使って、4指標を計算する。
                                                mStrategyID,      // 使用する取引の絞り込み要素
                                                mSymbol,          // 使用する取引の絞り込み要素。使用する指標の通貨ペアでもある。
                                                mTimeframe_calc,       // 使用するindextableを計算した時の時間軸
                                                mTargetTime,      // 計算基準時間
                                                mTargetTime - (mTargetTime * 60) * END_SHIFT  // どの時間から計算基準時間までの指標を平均と偏差の計算対象にするか。
                                                );
         if(flag_getStoc_vOrders == true) {  // 4指標のいずれかは計算できているはずなので、以下を実行する。
            // ⑤4指標を使ってステージnの仮想取引を登録
            //
            // 1) 計算基準時間mTargetTimeの指標値を取得する。
            mOpenTime  =  iTime(mSymbol, mTimeframe, shiftCounter);
            mOpenprice = iClose(mSymbol, mTimeframe, shiftCounter);
            st_vOrderIndex buf_st_vOrderIndexes;  // 計算した指標を格納する構造体。
            // 計算基準時点の指標を計算し、引数st_vOrderIndexesに代入する。
            bool flag_do_calc_Indexes = DB_do_calc_Indexes(
                                                           mSymbol,              // 入力：通貨ペア
                                                           mTimeframe,           //　入力：PERIOD_M1。price, index, 新規発注を行う間隔
                                                           mTimeframe_calc,      // 入力：指標の計算に使う時間軸。PERIOD_M15
                                                           mOpenTime,            // 入力：計算基準時間。datatime型。
                                                           buf_st_vOrderIndexes  // 出力：指標の計算結果。
                                                           );
                                                       
            // 現時点mOpenTimeの指標計算関数do_calc_Indexes失敗時。
            if(flag_do_calc_Indexes == false) {
               printf("[%d]テスト　　DB_do_calc_Indexes失敗", __LINE__);
            }
            // 現時点mOpenTimeの指標buf_st_vOrderIndexesが、計算できたので、売買可能かを判断する。。
            else { 
               // 2) 外部パラメータVT_JUDGEMETHOD の値に従って、売買可能かを判断する。
               // 判断パターン番号1：買い（売り）の範囲内の時、trueを返す。
               // 判断パターン番号2：買い（売り）の反対売買の範囲外
               // 判断パターン番号3：1,2の両立。買い（売り）の範囲内であって、反対売買の範囲外。
               bool blBUY_able = false;
               bool blSELL_able = false;
               bool flag_DB_judgeTradable =  DB_judgeTradable(
                                                   mStageID,             // 入力：判断を必要としているステージ番号
                                                   mStrategyID,
                                                   buf_st_vOrderIndexes, // 入力：判断時点の指標を格納した構造体。
                                                   blBUY_able,           // 出力：買いが可能な場合に、true
                                                   blSELL_able           // 出力：売りが可能な場合に、true
                                                );
string tempBuy ;
if(blBUY_able == true) {
   tempBuy = "買いOK";
}
else {
   tempBuy = "買いNG";
}
string tempSell ;
if(blSELL_able == true) {
   tempSell = "売りOK";
}
else {
   tempSell = "売りNG";
}
/*printf( "[%d]テスト 買い＝>%s<　売り＝>%s<  ←←　ステージ>%d<のシフト>%d::%s<の取引新規追加に向けたDB_judgeTradableの結果" , __LINE__,
                  tempBuy, tempSell,
                  mStageID, 
                  shiftCounter, 
                  TimeToStr(mTargetTime));         */
                                             
               // 3) ステージnの仮想取引を登録する。
               if(flag_DB_judgeTradable == true) {
                  if(blBUY_able == true) {
                     tickNo = DB_v_mOrderSend4(mOpenTime, mSymbol, OP_BUY,  LOTS, mOpenprice, SLIPPAGE, 0.0, 0.0, mStrategyID, 0, 0, LINE_COLOR_LONG);
                     // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出すwrite_vOrdersOnMemory(false)は、関数DB_v_mOrderSend4内で行っている。
                     if(tickNo <= 0) {
                        printf( "[%d]テスト mStageID == %d　買い仮想取引失敗" , __LINE__, mStageID);
                     }
                     else {
                        insertedTradeNum++;
//printf( "[%d]テスト mStageID == %d　売り仮想取引成功→>%d<件" , __LINE__, mStageID, insertedTradeNum);                        
                        
                     }
                  }
                  if(blSELL_able == true) {
                     tickNo = DB_v_mOrderSend4(mOpenTime, mSymbol, OP_SELL, LOTS, mOpenprice, SLIPPAGE, 0.0, 0.0, mStrategyID, 0, 0, LINE_COLOR_SHORT);
                     // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出すwrite_vOrdersOnMemory(false)は、関数DB_v_mOrderSend4内で行っている。
                     if(tickNo <= 0) {
                        printf( "[%d]テスト mStageID == %d　売り仮想取引失敗" , __LINE__, mStageID);
                     }
                     else {
                        insertedTradeNum++;
//printf( "[%d]テスト mStageID == %d　売り仮想取引成功→>%d<件" , __LINE__, mStageID, insertedTradeNum);                        
                     }
                  }
                  write_vOrdersOnMemory(false);  // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出す
               }     // if(flag_DB_judgeTradable == true) {
            } // else // 指標計算関数do_calc_Indexes成功時。
         }    // if(flag_getStoc_vOrders == true) {  // 4指標のいずれかは計算できているはずなので、以下を実行する。
         else {
printf( "[%d]テスト 4種の計算全滅。ステージ>%d<のシフト>%d::%s<の取引新規追加に向けて、ステージ>%d<のデータを使って計算したが全滅。" , __LINE__,
mStageID, shiftCounter, TimeToStr(mTargetTime), mStageID - 1);         
         
         }
      }       // for(shiftCounter = endShift; shiftCounter >= startShift; shiftCounter--) {
      // 構造体に入った仮想取引をテーブルに出力して、構造体をクリアする。
      write_vOrdersOnMemory(true); // st_vOrders[VTRADENUM_MAX]の利用状況によらず、テーブルに書き出す
   }         //mStageID > 0の場合
   
 
   return insertedTradeNum;
}



// do_calc_IndexesのDB版
// テーブルから読み込み、出力用引数の値をセットする。
bool DB_do_calc_Indexes(string         mSymbol,                 // 入力：通貨ペア
                        int            mTimeFrame,              //　PERIOD_M1。price, index, 新規発注を行う間隔
                        int            mTimeframe_calc,         // PERIOD_M15。指標を計算する時に使う時間軸
                        datetime       mcalcTime,               // 入力：計算基準時間。datatime型。
                        st_vOrderIndex &output_st_vOrderIndexes // 出力：指標の計算結果。
                       ) {
//printf( "[%d]テスト DB_do_calc_Indexesの引数確認=通貨>%s<  時間軸>%d<←1のはず  計算基準時間>%d< >%s<" , __LINE__, 
//             mSymbol, mTimeFrame, mcalcTime, TimeToStr(mcalcTime));
   // 登録された仮想取引をvtradetableに追加する。
   if(StringLen(mSymbol) > 0
      && mTimeFrame > 0 
      && mcalcTime> 0  ) {

      string Query = "";
      Query = Query + " select symbol, timeframe, calc_dt, calc_dt_str, MA_GC, MA_DC, MA_Slope5, MA_Slope25, MA_Slope75, BB_Width, IK_TEN, IK_CHI, IK_LEG, MACD_GC, MACD_DC, RSI_VAL, STOC_VAL, STOC_GC, STOC_DC, RCI_VAL from indextable ";
      Query = Query + " where ";
      Query = Query + " symbol = \'" + mSymbol + "\' ";
      Query = Query + " AND ";
      Query = Query + " timeframe = " + IntegerToString(mTimeframe_calc) + " ";
      Query = Query + " AND ";
      Query = Query + " calc_dt <= " + IntegerToString(mcalcTime) + " order by calc_dt DESC; ";

      int intCursor = MySqlCursorOpen(DB, Query);
      //カーソルの取得失敗時は後続処理をしない。
      if(intCursor < 0) {
         printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);
         return false;          
      }
      else {
         int Rows = MySqlCursorRows(intCursor);
         if(Rows > 0) {
            if (MySqlCursorFetchRow(intCursor)) {
               // カーソルの指す1件を取得する。
               // 
               output_st_vOrderIndexes.symbol      = MySqlGetFieldAsString(intCursor, 0);
               output_st_vOrderIndexes.timeframe   = MySqlGetFieldAsInt(intCursor,    1);
               output_st_vOrderIndexes.calcTime     = MySqlGetFieldAsInt(intCursor,    2);
               // 計算時間の文字列型 = MySqlGetFieldAsString(intCursor, 3);
               output_st_vOrderIndexes.MA_GC = MySqlGetFieldAsInt(intCursor, 4);
               output_st_vOrderIndexes.MA_DC = MySqlGetFieldAsInt(intCursor, 5);
               output_st_vOrderIndexes.MA_Slope5 =  MySqlGetFieldAsInt(intCursor, 6);
               output_st_vOrderIndexes.MA_Slope25 =  MySqlGetFieldAsInt(intCursor, 7);
               output_st_vOrderIndexes.MA_Slope75 =  MySqlGetFieldAsInt(intCursor, 8);
               output_st_vOrderIndexes.BB_Width =  MySqlGetFieldAsInt(intCursor, 9);
               output_st_vOrderIndexes.IK_TEN =  MySqlGetFieldAsInt(intCursor,10);
               output_st_vOrderIndexes.IK_CHI =  MySqlGetFieldAsInt(intCursor,11);
               output_st_vOrderIndexes.IK_LEG =  MySqlGetFieldAsInt(intCursor,12);
               output_st_vOrderIndexes.MACD_GC = MySqlGetFieldAsInt(intCursor,13);
               output_st_vOrderIndexes.MACD_DC = MySqlGetFieldAsInt(intCursor,14);
               output_st_vOrderIndexes.RSI_VAL =  MySqlGetFieldAsInt(intCursor,15);
               output_st_vOrderIndexes.STOC_VAL =  MySqlGetFieldAsInt(intCursor,16);
               output_st_vOrderIndexes.STOC_GC = MySqlGetFieldAsInt(intCursor,17);
               output_st_vOrderIndexes.STOC_DC = MySqlGetFieldAsInt(intCursor,18);
               output_st_vOrderIndexes.RCI_VAL =  MySqlGetFieldAsInt(intCursor,19);
            }
         }
      }
      MySqlCursorClose(intCursor);
   }
   else {
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| 仮想取引の新規発注をする　　　                                   |
//+------------------------------------------------------------------+
// Tigris_VirtualTrade.v_mOrderSend4のDB連携版。
// 内部で仮想取引を配列上に登録するv_OrderSendを実行した結果、st_vOrders[VTRADENUM_MAX]に仮想取引が登録される。
// その際、仮想取引が、VTRADENUM_MAX - 10を超えたとき、関数DB_update_vtradetable()を使って、
// 仮想取引をvtradetableテーブルに書き出し、st_vOrders[]をクリアする。
int DB_v_mOrderSend4(datetime mOpenTime,
                  string symbol, 
                  int cmd, 
                  double volume, 
                  double price, 
                  int slippage, 
                  double stoploss, 
                  double takeprofit, 
                  string comment, 
                  int magic, 
                  datetime expiration, 
                  color arrow_color) {
   bool mFlag = false;
   int Index = 0;
   int total_vOrdersNum = 0;
   int ticket_num =-1;
   int ii = 0;
   double ATR_1 = 0.0;
   double mOpen4Modify = 0.0;
   double mTP4Modify = 0.0;
   double mSL4Modify = 0.0;

   //初期値設定
   double mMarketinfoMODE_ASK = 0.0;
   double mMarketinfoMODE_BID = 0.0;
   double mMarketinfoMODE_POINT = 0.0;
   double mMarketinfoMODE_STOPLEVEL = 0.0;
   int barShift  = iBarShift(symbol, PERIOD_M1, mOpenTime, false); 

   if(cmd == OP_BUY || cmd == OP_SELL)  {
      // 約定日に使用としている引数mOpenTimeが、
      // ①現在のバー(バー = 0)であれば、MODE_ASKとMODE_BIDの値を取得する。
      // ②現在のバーでなければ、当時のバーのclose値をASK, BIDの値とする。
      if(barShift == 0) {
         mMarketinfoMODE_ASK = MarketInfo(symbol,MODE_ASK);
         mMarketinfoMODE_BID = MarketInfo(symbol,MODE_BID);
      }
      else {
         mMarketinfoMODE_ASK = iClose(global_Symbol, PERIOD_M1, barShift);
         mMarketinfoMODE_BID = iClose(global_Symbol, PERIOD_M1, barShift);
      }
      mMarketinfoMODE_POINT = global_Points;
      mMarketinfoMODE_STOPLEVEL = global_StopLevel;
   }
   else {
      return ERROR;
   }

   // takeprofitとstoplossを0.0として、OrderSendを実行する。
   // takeprofitとstoplosslへの変更は、OrderSend成功後にOrderModifyを使う。
   // v_OrderSendは、返り値として、st_vOrders[].ticketを返す。失敗したときは、-1を返す。
   // string commentは、21:RCISWING, 20:TrendBB, 19:MoveSpeedなどを設定する。
   ticket_num = DB_v_OrderSend(mOpenTime, symbol, cmd, volume, price, slippage, 0.0, 0.0, comment, magic, expiration, arrow_color);
   if(ticket_num <= 0) {
      printf("[%d]エラー 仮想OrderSend失敗：：%s", __LINE__);
      return ERROR_ORDERSEND;
   }


   // 引数takeprofitとstoplossが0以下の時は、tpとslを設定しないで正常終了。
   if(takeprofit <= 0.0 && stoploss <= 0.0) {
      write_vOrdersOnMemory(false);  // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出す
      return ticket_num;
   }

   // 外部変数TP_PIPSとSL_PIPSが0以下の時は、tpとslを設定しないで正常終了。
   if(TP_PIPS <= 0 && SL_PIPS <= 0) {
      write_vOrdersOnMemory(false);  // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出す
      return ticket_num;
   }

   //
   // 以下は、引数takeprofitとstoplossを使った指値変更処理
   //

   // ロングの利確takeprofitは、その時のASK＋ストップレベルより大きくなくてはならない。
   // ロングの損切stoploss　は、その時のBID-ストップレベルより小さくなくてはならない。
   // 参考資料：https://toushi-strategy.com/mt4/stoplevel/
   //
   int modifyIndex = -1;
   int i;
   if(cmd == OP_BUY)  {

      // takeprofitとstoploss両方が条件を満たす場合。
      if(NormalizeDouble(takeprofit, global_Digits)  > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits)  + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT
         &&
         NormalizeDouble(stoploss, global_Digits)  < NormalizeDouble(mMarketinfoMODE_BID, global_Digits)  - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT)  {
         // st_vOrders[].ticket = ticket_numを満たす要素を更新する。
         for(i = 0; i < VTRADENUM_MAX; i++)  {
            if(st_vOrders[i].ticket == ticket_num)  {
               st_vOrders[i].orderTakeProfit = NormalizeDouble(takeprofit, global_Digits); // 利益確定の値
               st_vOrders[i].orderStopLoss   = NormalizeDouble(stoploss, global_Digits);   // 損切の値
               write_vOrdersOnMemory(false);  // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出す
               return ticket_num;
            }
         }
      }

      // takeprofitのみが条件を満たす場合。
      if(NormalizeDouble(takeprofit, global_Digits)  > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits)  + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT 
         &&
         NormalizeDouble(stoploss, global_Digits)  >=  NormalizeDouble(mMarketinfoMODE_BID, global_Digits)  - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT)  {
         // st_vOrders[].ticket = ticket_numを満たす要素を更新する。
         for(i = 0; i < VTRADENUM_MAX; i++)  {
            if(st_vOrders[i].ticket == ticket_num)  {
               st_vOrders[i].orderTakeProfit = NormalizeDouble(takeprofit, global_Digits); // 利益確定の値
               write_vOrdersOnMemory(false);  // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出す
               return ticket_num;
            }
         }
      }
      // stoplossのみが条件を満たす場合。
      else if(
            NormalizeDouble(takeprofit, global_Digits) <= NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT
            &&
            NormalizeDouble(stoploss, global_Digits)   <  NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT)  {
            // st_vOrders[].ticket = ticket_numを満たす要素を更新する。
            for(i = 0; i < VTRADENUM_MAX; i++) {
               if(st_vOrders[i].ticket == ticket_num) {
                  st_vOrders[i].orderStopLoss = NormalizeDouble(stoploss, global_Digits);   // 損切の値
                  write_vOrdersOnMemory(false);  // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出す
                  return ticket_num;
               }
            }
         }
         // takeprofitとstoploss両方が条件を満たさない場合は、何もしない。
         else  {
         }
   }  // ロングの場合の指値変更処理は、ここまで。

   // ショートの利確takeprofitは、その時のBID-ストップレベルより小さくなくてはならない。
   // ショートの損切stoplossは、その時のASK+ストップレベルより大きくなくてはならない。
   // 参考資料：https://toushi-strategy.com/mt4/stoplevel/　　から、推測。
   if(cmd == OP_SELL) {
      // takeprofitとstoploss両方が条件を満たす場合。
      if(NormalizeDouble(takeprofit, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT 
         &&
         NormalizeDouble(stoploss, global_Digits)   > NormalizeDouble(mMarketinfoMODE_BID, global_Digits) + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT)  {
         // st_vOrders[].ticket = ticket_numを満たす要素を更新する。
         for(i = 0; i < VTRADENUM_MAX; i++)  {
            if(st_vOrders[i].ticket == ticket_num)  {
               st_vOrders[i].orderTakeProfit = NormalizeDouble(takeprofit, global_Digits); // 利益確定の値
               st_vOrders[i].orderStopLoss   = NormalizeDouble(stoploss, global_Digits);   // 損切の値
               write_vOrdersOnMemory(false);  // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出す
               return ticket_num;
            }
         }
      }

      // takeprofitのみが条件を満たす場合。
      else if(
            NormalizeDouble(takeprofit, global_Digits) <  NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT 
            &&
            NormalizeDouble(stoploss, global_Digits)  <= NormalizeDouble(mMarketinfoMODE_BID, global_Digits) + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT)  {
            // st_vOrders[].ticket = ticket_numを満たす要素を更新する。
            for(i = 0; i < VTRADENUM_MAX; i++)  {
               if(st_vOrders[i].ticket == ticket_num)  {
                  st_vOrders[i].orderTakeProfit = NormalizeDouble(takeprofit, global_Digits); // 利益確定の値
                  write_vOrdersOnMemory(false);  // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出す
                  return ticket_num;
               }
            }
      }

      // stoplossのみが条件を満たす場合。
      else if(
               NormalizeDouble(takeprofit, global_Digits) >= NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT 
               &&
               NormalizeDouble(stoploss, global_Digits) >  NormalizeDouble(mMarketinfoMODE_BID, global_Digits) + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT)  {
               // st_vOrders[].ticket = ticket_numを満たす要素を更新する。
               for(i = 0; i < VTRADENUM_MAX; i++)  {
                  if(st_vOrders[i].ticket == ticket_num)  {
                     st_vOrders[i].orderStopLoss = NormalizeDouble(stoploss, global_Digits);   // 損切の値
                     write_vOrdersOnMemory(false);  // st_vOrders[VTRADENUM_MAX]が、満杯に近ければ、テーブルに書き出す
                     return ticket_num;
                  }
               }
      }
      // takeprofitとstoploss両方が条件を満たさない場合は、何もしない。
      else {
      }
   }

   if(ticket_num > 0) {
      total_vOrdersNum  = get_vOrdersNum();
      if(total_vOrdersNum >= VTRADENUM_MAX - 10) {
         DB_update_vtradetable();
         for(ii = 0; ii < VTRADENUM_MAX; ii++){
            init_st_vOrders(ii);
         }
      }

      return ticket_num;
   }
   else {
      printf("[%d]エラー 仮想取引失敗", __LINE__);
      return ERROR;
   }
}

// v_OrderSendのDB版
// チケット番号にグローバル変数global_TickNoを使う
int DB_v_OrderSend(datetime mOpenTime,
                string symbol,
                int cmd,
                double volume,
                double price,
                int slippage,
                double stoploss,
                double takeprofit,
                string comment,
                int magic,
                datetime expiration,
                color arrow_color) {
   int i = 0;
   if(StringLen(comment) <= 0) {
      printf("[%d]エラー キーワード未設定のため、仮想取引を追加できません", __LINE__);
      return -1;
   }

   // 配列のうち、使っていないところを探す。
   int newTradeIndex = -1;
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0) {
         newTradeIndex = i;
         break;
      }
   }
   if(newTradeIndex >= VTRADENUM_MAX) {
      printf("[%d]エラー 仮想取引を追加できません", __LINE__);
      return -1;
   }
   else if(newTradeIndex < 0) {
         newTradeIndex = 0;
   }

   // 仮想取引を追加する
   st_vOrders[newTradeIndex].strategyID = comment;      // 21:RCISWING, 20:TrendBB, 19:MoveSpeedなど
   st_vOrders[newTradeIndex].symbol = symbol;           // EURUSD-CDなど
   st_vOrders[newTradeIndex].ticket = global_TickNo;    // チケット番号
   global_TickNo = global_TickNo + 1;                   // チケット番号を更新する。
   st_vOrders[newTradeIndex].timeframe = global_Period4vTrade; // 時間軸。
   st_vOrders[newTradeIndex].orderType = cmd;           // OP_BUYかOPSELL
   st_vOrders[newTradeIndex].openTime = mOpenTime;      // 約定日時。datetime型。
   st_vOrders[newTradeIndex].lots = volume;             // ロット数
   st_vOrders[newTradeIndex].openPrice = NormalizeDouble(price, global_Digits);       // 新規建て時の値
   st_vOrders[newTradeIndex].orderTakeProfit = NormalizeDouble(takeprofit, global_Digits); // 利益確定の値
   st_vOrders[newTradeIndex].orderStopLoss   = NormalizeDouble(stoploss, global_Digits);   // 損切の値
   st_vOrders[newTradeIndex].closePrice = 0.0;      // 決済値
   st_vOrders[newTradeIndex].closeTime = 0;     // 決済日時。datetime型。

   return st_vOrders[newTradeIndex].ticket;
}





// st_vOrders[VTRADENUM_MAX]をテーブルに書き出し、初期化する。
// 引数blWriteAll = falseの時、st_vOrders[VTRADENUM_MAX]が満杯近ければ、テーブルに書き出す。
// 引数blWriteAll = false以外の時、st_vOrders[VTRADENUM_MAX]が満杯かどうかによらず、テーブルに書き出す。
void write_vOrdersOnMemory(bool blWriteAll) {
   int ii;
   if(blWriteAll == false) {   // st_vOrders[VTRADENUM_MAX]が満杯近ければ、テーブルに書き出す。
      int total_vOrdersNum  = get_vOrdersNum();
      if(total_vOrdersNum >= VTRADENUM_MAX - 10
         || total_vOrdersNum >=  VTRADENUM_MAX * 0.95) {
         DB_update_vtradetable();
         for(ii = 0; ii < VTRADENUM_MAX; ii++){  // 出力したので、メモリをクリアする
            init_st_vOrders(ii);
         }
      }
      else {
         // 引数blWriteAllがtrueではなく、st_vOrders[VTRADENUM_MAX]が満杯でもなければ、何もしない。
      }
   }
   else {  // st_vOrders[VTRADENUM_MAX]が満杯かどうかによらず、テーブルに書き出す。
      DB_update_vtradetable();
      for(ii = 0; ii < VTRADENUM_MAX; ii++){  // 出力したので、メモリをクリアする
         init_st_vOrders(ii);
      }
   }
}

// st_vOrders[VTRADENUM_MAX]に登録された仮想取引をvtradetableテーブルに書き出し、st_vOrders[]をクリアする。
// 処理件数を返す。
int DB_update_vtradetable() {
   int i;
   int updatedTradeNum = 0;
   int num = get_vOrdersNum();
   if(num <= 0) {
      return num;
   }

   string Query;
   for(i = 0; i < VTRADENUM_MAX; i++){
      // 登録された仮想取引をvtradetableに追加する。
      if(st_vOrders[i].openTime > 0 
         && StringLen(st_vOrders[i].strategyID) > 0  
         && StringLen(st_vOrders[i].symbol) > 0  
         ) {
         Query = "INSERT INTO `vtradetable` (stageID, strategyID, symbol, ticket, timeframe, orderType, openTime, openTime_str, lots, openPrice, orderTakeProfit, orderStopLoss, closePrice, closeTime, closeTime_str, closePL, estimatePrice, estimateTime, estimateTime_str, estimatePL) VALUES ("+ 
            	IntegerToString(global_stageID) + ", " +	  //ステージ番号
                "\'" + st_vOrders[i].strategyID + "\', " +              //戦略名
                "\'" + st_vOrders[i].symbol + "\', " +                  //通貨ペア
            	IntegerToString(st_vOrders[i].ticket) + ", " +	  //チケット番号
            	IntegerToString(st_vOrders[i].timeframe) + ", " +	  //タイムフレーム
            	IntegerToString(st_vOrders[i].orderType) + ", " +	  //OP_BUYかOPSELL
            	IntegerToString(st_vOrders[i].openTime) + ", " +	  //約定時間。datatime型。
            	"\'" + TimeToStr(st_vOrders[i].openTime) + "\', " +     //約定時間。文字列
                DoubleToStr(st_vOrders[i].lots) + ", " +	          //ロット数
                "truncate ("+ DoubleToStr(NormalizeDouble(st_vOrders[i].openPrice, global_Digits), global_Digits) + ", 5), " +	       //約定値
                DoubleToStr(NormalizeDouble(st_vOrders[i].orderTakeProfit, global_Digits), global_Digits) + ", " +  //利確値
                DoubleToStr(NormalizeDouble(st_vOrders[i].orderStopLoss, global_Digits), global_Digits) + ", " +    //損切値
                DoubleToStr(NormalizeDouble(st_vOrders[i].closePrice, global_Digits), global_Digits) + ", " +       //決済値
            	IntegerToString(st_vOrders[i].closeTime) + ", " +	   //決済時間。datatime型。
            	"\'" + TimeToStr(st_vOrders[i].closeTime) + "\', " +     //決済時間。文字列
                DoubleToStr(NormalizeDouble(st_vOrders[i].closePL, global_Digits), global_Digits) + ", " +          //決済損益
                DoubleToStr(NormalizeDouble(st_vOrders[i].estimatePrice, global_Digits), global_Digits) + ", " +    //評価値
            	IntegerToString(st_vOrders[i].estimateTime) + ", " +	   //評価時間。datatime型。
            	"\'" + TimeToStr(st_vOrders[i].estimateTime) + "\', " +  //評価時間。文字列
                DoubleToStr(NormalizeDouble(st_vOrders[i].estimatePL, global_Digits), global_Digits)  +             //評価損益
              ")";
           
         //SQL文を実行
       	if (MySqlExecute(DB, Query) == true) {
       	   updatedTradeNum++;
         }
         else {
            printf( "[%d]エラー　追加失敗:%s" , __LINE__, MySqlErrorDescription);              
            printf( "[%d]エラー　追加失敗時のSQL:%s" , __LINE__, Query);              
         }

         init_st_vOrders(i);
      }
   }
   return updatedTradeNum;
}


// vtradetableテーブルに登録された仮想取引のうち、引数mStrategyID, mSymbol, mTimeFrameをキーとして持ち、
// 約定時間openTimeが、mFrom_openTime～mTo_openTimeの個数を返す。
int DB_getNumber_of_vOrders(int      mStageID,        // 入力：ステージ番号
                            string   mStrategyID,     // 入力：戦略名
                            string   mSymbol,         // 入力：EURUSD-CDなど
                            int      mTimeFrame,      //　入力：PERIOD_M1。price, index, 新規発注を行う間隔
                            datetime mFrom_openTime,  // 入力：仮想取引の約定時間がこの値以降。
                            datetime mTo_openTime     // 入力：仮想取引の約定時間がこの値以前。現時点(i)より1つ以上過去を探す。
                            ) {
   if(StringLen(mStrategyID) <= 0  
      || StringLen(mSymbol) <= 0) {
      return 0;
   }  
   if(mFrom_openTime < 0 || mTo_openTime < 0) {
      return 0;
   }  
   if(mFrom_openTime > mTo_openTime) {
      return 0;
   }  

   int num = 0;

   if (DB == -1) {
      printf( "[%d]エラー　接続失敗:%s" , __LINE__, MySqlErrorDescription);      
   }

   else {
      string strBuf = "select count(*) from vtradetable where " +
               "stageID = " + IntegerToString(mStageID) + " and "+
               "strategyID = \'" + mStrategyID + "\' and " +
               "symbol = \'" + mSymbol + "\' and " +
               "timeframe = " + IntegerToString(mTimeFrame) + " and "+
               "openTime  >= " + IntegerToString(mFrom_openTime) + " and "+
               "openTime  <= " + IntegerToString(mTo_openTime) + ";" ;
      int intCursor = MySqlCursorOpen(DB, strBuf);
   
      //カーソルの取得失敗時は後続処理をしない。
      if(intCursor < 0) {
         printf( "[%d]エラー　カーソルオープン失敗:%s" , __LINE__, MySqlErrorDescription, strBuf);              
      }
      else {
         //カーソルの指す1件を取得する。
         int Rows = MySqlCursorRows(intCursor);
         if(Rows > 0) {
            bool cursolFlag = MySqlCursorFetchRow(intCursor);
            if(cursolFlag == false) {
               printf( "[%d]エラー　select文失敗:%s:%s" , __LINE__, MySqlErrorDescription, strBuf);              
            }
            else {
               num = MySqlGetFieldAsInt(intCursor, 0);
            }
         }
      }
      MySqlCursorClose(intCursor);
   }

   return num;
}


// 引数で指定した戦略、通貨ペア、時間軸、基準時間で各指標を計算し、
// 引数m_st_vOrderIndexに格納するv_calcIndexesのDB版。
// indextableテーブルに格納された計算結果を検索して、
// 出力表引数m_st_vOrderIndexにセットする。
// 引数mCalcTimeが、指標を計算する基準時間。
// 何からの計算に失敗した場合は、falseを返す。それ以外は、true。
bool DB_v_calcIndexes(string mStrategyID,                // 入力：戦略名
                      string mSymbol,                    // 入力：通貨ペア
                      int mTimeframe_calc,               // 入力：PERIOD_M15。指標を計算する時に使う時間軸
                      datetime mCalcTime,                // 入力：計算基準日
                      st_vOrderIndex &m_st_vOrderIndex)  // 出力：計算結果を格納する構造体
  {
   if(StringLen(mStrategyID) <= 0)  {
      return false;
   }
   if(mTimeframe_calc < 0) {
      return false;
   }

   bool rtnFlag = true;

   if (DB == -1) {
      printf( "[%d]エラー　接続失敗:%s" , __LINE__, MySqlErrorDescription);      
      rtnFlag = false;
   }

   else {
      string strBuf = "select symbol, timeframe, calc_dt, calc_dt_str, MA_GC, MA_DC, MA_Slope5, MA_Slope25, MA_Slope75, BB_Width, IK_TEN, IK_CHI, IK_LEG, MACD_GC, MACD_DC, RSI_VAL, STOC_VAL, STOC_GC, STOC_DC, RCI_VAL from indextable where " +
               "strategyID = \'" + mStrategyID + "\' and " +
               "symbol = \'" + mSymbol + "\' and " +
               "timeframe = " + IntegerToString(mTimeframe_calc) + " and "+
               "calc_dt = " + IntegerToString(mCalcTime) + " ;" ;


      int intCursor = MySqlCursorOpen(DB, strBuf);
   
      //カーソルの取得失敗時は後続処理をしない。
      if(intCursor < 0) {
         rtnFlag = false;
         printf( "[%d]エラー　カーソルオープン失敗:%s" , __LINE__, MySqlErrorDescription);              
      }
      else {
         int Rows = MySqlCursorRows(intCursor);
         if(Rows > 0) {
            //カーソルの指す1件を取得する。
            bool cursolFlag = MySqlCursorFetchRow(intCursor);
            if(cursolFlag == false) {
               rtnFlag = false;
               printf( "[%d]エラー　select文失敗:%s:%s" , __LINE__, MySqlErrorDescription, strBuf);              
            }
            else {
               m_st_vOrderIndex.symbol     = MySqlGetFieldAsString(intCursor, 0);
               m_st_vOrderIndex.timeframe  = MySqlGetFieldAsInt(intCursor, 1);
               m_st_vOrderIndex.calcTime   = MySqlGetFieldAsDatetime(intCursor, 2);
               //m_st_vOrderIndex.calc_dt_str = MySqlGetFieldAsString(intCursor, 3);
               m_st_vOrderIndex.MA_GC      = MySqlGetFieldAsInt(intCursor, 4);
               m_st_vOrderIndex.MA_DC      = MySqlGetFieldAsInt(intCursor, 5);
               m_st_vOrderIndex.MA_Slope5  = MySqlGetFieldAsDouble(intCursor, 6);
               m_st_vOrderIndex.MA_Slope25 = MySqlGetFieldAsDouble(intCursor, 7);
               m_st_vOrderIndex.MA_Slope75 = MySqlGetFieldAsDouble(intCursor, 8);
               m_st_vOrderIndex.BB_Width   = MySqlGetFieldAsDouble(intCursor, 9);
               m_st_vOrderIndex.IK_TEN     = MySqlGetFieldAsDouble(intCursor, 10);
               m_st_vOrderIndex.IK_CHI     = MySqlGetFieldAsDouble(intCursor, 11);
               m_st_vOrderIndex.IK_LEG     = MySqlGetFieldAsDouble(intCursor, 12);
               m_st_vOrderIndex.MACD_GC    = MySqlGetFieldAsInt(intCursor, 13);
               m_st_vOrderIndex.MACD_DC    = MySqlGetFieldAsInt(intCursor, 14);
               m_st_vOrderIndex.RSI_VAL    = MySqlGetFieldAsDouble(intCursor, 15);
               m_st_vOrderIndex.STOC_VAL   = MySqlGetFieldAsDouble(intCursor, 16);
               m_st_vOrderIndex.STOC_GC    = MySqlGetFieldAsInt(intCursor, 17);
               m_st_vOrderIndex.STOC_DC    = MySqlGetFieldAsInt(intCursor, 18);
               m_st_vOrderIndex.RCI_VAL    = MySqlGetFieldAsDouble(intCursor, 19);
            }
         }
      }
      MySqlCursorClose(intCursor);
   }

   return rtnFlag;
}




// 引数で特定できる値をpricetableテーブルから削除する。
bool DB_delete_price(string   mSymbol,     // 削除する通貨ペア。長さ0の時は、通貨ペア名を削除条件に加えない。
                  int      mTimeframe,  // 削除する通貨ペアの時間軸。負の時は、削除条件に加えない
                  datetime mStartDt,    // 削除対象とするデータのpricetable.dt開始位置
                  datetime mEndDt       // 削除対象とするデータのpricetable.dt終了位置            
                 ) {
   string bufCondition = "";

   // 通貨ペア名
   if(StringLen(mSymbol) <= 0) { // 長さ0の時は、通貨ペア名を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " symbol = \'" + mSymbol + "\' ";
   }

   // 時間軸
   if(mTimeframe < 0) {  // 負の時は、チケット番号を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " timeframe = " + IntegerToString(mTimeframe);
   }

   // 開始位置
   if(mStartDt < 0) {  // 負の時は、チケット番号を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " dt >= " + IntegerToString(mStartDt);
   }

   // 終了位置
   if(mEndDt < 0) {  // 負の時は、チケット番号を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " dt <= " + IntegerToString(mEndDt);
   }
   
   
   string Query = "delete from pricetable";
   if(StringLen(bufCondition) > 0) {
      Query = Query + " where " + bufCondition;
   }

// printf( "[%d]テスト　delete_vTradeの削除用SQL:%s" , __LINE__, Query);     

   if (MySqlExecute(DB,Query) == true) {
      return true;
   }
   else {
      printf( "[%d]エラー  delete_pricee削除失敗=%s" , __LINE__ ,MySqlErrorDescription);
      return false;
   }
}



// 引数で特定できる仮想取引をindextableテーブルから削除する。
bool DB_delete_index(string   mSymbol,    // 仮想取引の通貨ペア。長さ0の時は、戦略名を削除条件に加えない。
                     int      mTimeframe_calc, // PERIOD_M15。指標を計算する時に使う時間軸
                     datetime mStartDt,   // 削除対象とするデータのindextable.calc_dt開始位置
                     datetime mEndDt      // 削除対象とするデータのindextable.calc_dt終了位置            
                 ) {
   string bufCondition = "";


   // 通貨ペア名
   if(StringLen(mSymbol) <= 0) { // 長さ0の時は、通貨ペア名を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " symbol = \'" + mSymbol + "\' ";
   }

   // 時間軸
   if(mTimeframe_calc < 0) {  // 負の時は、チケット番号を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " timeframe = " + IntegerToString(mTimeframe_calc);
   }

   // 開始位置
   if(mStartDt < 0) {  // 負の時は、チケット番号を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " calc_dt >= " + IntegerToString(mStartDt);
   }

   // 終了位置
   if(mEndDt < 0) {  // 負の時は、チケット番号を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " calc_dt <= " + IntegerToString(mEndDt);
   }


   string Query = "delete from indextable";
   if(StringLen(bufCondition) > 0) {
      Query = Query + " where " + bufCondition;
   }

//printf( "[%d]テスト　delete_indexの削除用SQL:%s" , __LINE__, Query);     

   if (MySqlExecute(DB,Query) == true) {
      return true;
   }
   else {
      printf( "[%d]エラー  delete_index削除失敗=%s" , __LINE__ ,MySqlErrorDescription);
      return false;
   }
}


// 引数で特定できる仮想取引をvtradetableテーブルから削除する。
bool DB_delete_vTrade(int    mStageID,    // ステージ番号。正の時は、この番号以上のステージのデータを削除。負の時は、ステージ番号を削除条件に加えない。
                   string mstrategyID, // 戦略名。　　　長さ0の時は、戦略名を削除条件に加えない。
                   int    tickNo,      // チケット番号。負の時は、ステージ番号を削除条件に加えない。
                   string symbolName,  // 仮想取引の通貨ペア。長さ0の時は、戦略名を削除条件に加えない。
                   int    mTimeframe,  // PERIOD_M1。price, index, 新規発注を行う間隔
                   int    mOrderType   // 売買区分。旧mBuySell　　OP_BUY及びOP_SELL以外の時は、区分を削除条件に加えない。
                 ) {
   string bufCondition = "";

   // ステージ番号
   if(mStageID < 0) {  // 負の時は、ステージ番号を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " stageID >= " + IntegerToString(mStageID);
   }
    
   // 戦略名
   if(StringLen(mstrategyID) <= 0) { // 長さ0の時は、戦略名を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " strategyID = \'" + mstrategyID + "\' ";
   }
  
   // チケット番号
   if(tickNo < 0) {  // 負の時は、チケット番号を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " ticket = " + IntegerToString(tickNo);
   }

   // 通貨ペア名
   if(StringLen(symbolName) <= 0) { // 長さ0の時は、通貨ペア名を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " symbol = \'" + symbolName + "\' ";
   }

   // 時間軸
   if(mTimeframe < 0) {  // 負の時は、チケット番号を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " timeframe = " + IntegerToString(mTimeframe);
   }

   // 売買区分
   if(mOrderType != OP_BUY && mOrderType != OP_SELL) {  // OP_BUY, OP_SELL以外の時は、削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " orderType = " + IntegerToString(mOrderType);
   }   

   string Query = "delete from vtradetable";
   if(StringLen(bufCondition) > 0) {
      Query = Query + " where " + bufCondition;
   }

// printf( "[%d]テスト　delete_vTradeの削除用SQL:%s" , __LINE__, Query);     

   if (MySqlExecute(DB,Query) == true) {
      return true;
   }
   else {
      printf( "[%d]エラー  delete_vTrade削除失敗=%s" , __LINE__ ,MySqlErrorDescription);
      return false;
   }
}


// チケット番号を意味するグローバル変数global_TickNoを、vtradetableテーブルに登録済みのチケット番号の最大値+1にする。
void DB_update_global_TickNo() {
   string strBuf = "select max(ticket) from vtradetable;";
   int intCursor = MySqlCursorOpen(DB, strBuf);
   if(intCursor < 0) {
      global_TickNo = 1;
   }
   else {
      //カーソルの指す1件を取得する。
      bool cursolFlag = MySqlCursorFetchRow(intCursor);
      if(cursolFlag == false) {
         global_TickNo = 1;
         printf( "[%d]エラー　select文失敗:%s:%s" , __LINE__, MySqlErrorDescription, strBuf); 
      }
      else {
         int Rows = MySqlCursorRows(intCursor);
         if(Rows <= 0) {
            global_TickNo = 1;
         }
         else {
            global_TickNo = MySqlGetFieldAsInt(intCursor, 0) + 1;
         }
      }
   }
   MySqlCursorClose(intCursor);
}


//+----------------------------------------------------------------------+
//| 仮想取引の利確、損切を設定する                                                |
//| DB版。                                                                |
//| ・当初は、引数で渡した基準日以前の約定に限定して、当時のcloseを使って指値と逆指値の計算をしていたが、 |
//|  mTPとmSLを使って一律に指値と逆指値を設定することとした。                               |
//|　・処理対象は、引数で渡したmStageID、mStrategyID、mSymbol, mTimeframeを持つ仮想取引とする。         |
//+---------------------------------------------------------------------+
bool DB_v_setAllOrdersTPSL(int    mStageID,         // 処理対象とする仮想取引のステージ番号
                           string mStrategyID, 
                           string mSymbol,
                           int    mTimeframe, //　PERIOD_M1。price, index, 新規発注を行う間隔
                           double mTP, 
                           double mSL)  {
   // 引数チェック
   if(mTP < 0 && mSL < 0)  {
      return false;
   }
   
   string Query = "";
   
   // 買い取引の指値設定用set文
   string buf_TP_BUY = "";
   if(mTP >= 0)  {
      buf_TP_BUY = "orderTakeProfit = truncate(openPrice + " + DoubleToStr(mTP * global_Points) + ", " + IntegerToString(global_Digits) + ") ";
   }
   else {
      buf_TP_BUY = "";
   }   

   // 買い取引の逆指値設定用set文
   string buf_SL_BUY = "";
   if(mSL >= 0)  {
      buf_SL_BUY = "orderStopLoss = truncate(openPrice - " + DoubleToStr(mSL * global_Points) + ", " + IntegerToString(global_Digits) + ") ";
   }
   else {
      buf_SL_BUY = "";
   }   
   
   // 買い取引の指値と逆指値の更新
   if(StringLen(buf_TP_BUY) <= 0 && StringLen(buf_SL_BUY) <= 0) {
      // 両方変更する予定がないので何もしない。
   }
   else {
      Query = "update vtradetable";
      // 指値のみ更新する場合
      if(StringLen(buf_TP_BUY) > 0 && StringLen(buf_SL_BUY) <= 0) {
         Query = Query + " SET " + buf_TP_BUY;
      }
      // 逆指値のみ更新する場合
      else if(StringLen(buf_TP_BUY) <= 0 && StringLen(buf_SL_BUY) > 0) {
         Query = Query + " SET " + buf_SL_BUY;
      }
      // 指値と逆指値両方更新する場合
      else {
         Query = Query + " SET " + buf_TP_BUY + ", " + buf_SL_BUY;
      }
      // 買い取引全体が更新対象のため、キー項目はstageID, strategyID, symbol, timeframe, orderTypeのみ。ticketは、条件としない。
      Query = Query + " where stageID = " + IntegerToString(mStageID) + " and "+
                      " strategyID = \'" + mStrategyID + "\' and " +
                                    " symbol = \'" + mSymbol + "\' and " +
                                    " timeframe = " + IntegerToString(mTimeframe) + " and " +
                                    " orderType = " + IntegerToString(OP_BUY) + " ;";
   }

   // テーブルの更新処理
   if(MySqlExecute(DB, Query) == true) {
//      printf( "[%d]テスト　買い取引の指値と逆指値の更新成功=%s" , __LINE__ , Query);   
   }
   else {
      printf( "[%d]エラー　買い取引の指値と逆指値の更新失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);              
   }
   

   // 売り取引の指値設定用set文
   string buf_TP_SELL = "";
   if(mTP >= 0)  {
      buf_TP_SELL = "orderTakeProfit = truncate(openPrice - " + DoubleToStr(mTP * global_Points) + ", " + IntegerToString(global_Digits) + ") ";
   }
   else {
      buf_TP_SELL = "";
   }   

   // 売り取引の逆指値設定用set文
   string buf_SL_SELL = "";
   if(mSL >= 0)  {
      buf_SL_SELL = "orderStopLoss = truncate(openPrice + " + DoubleToStr(mSL * global_Points) + ", " + IntegerToString(global_Digits) + ") ";
   }
   else {
      buf_SL_SELL = "";
   }   
   // 売り取引の指値と逆指値の更新
   if(StringLen(buf_TP_SELL) <= 0 && StringLen(buf_SL_SELL) <= 0) {
      // 両方変更する予定がないので何もしない。
   }
   else {
      Query = "update vtradetable";
      // 指値のみ更新する場合
      if(StringLen(buf_TP_SELL) > 0 && StringLen(buf_SL_SELL) <= 0) {
         Query = Query + " SET " + buf_TP_SELL;
      }
      // 逆指値のみ更新する場合
      else if(StringLen(buf_TP_BUY) <= 0 && StringLen(buf_SL_BUY) > 0) {
         Query = Query + " SET " + buf_SL_SELL;
      }
      // 指値と逆指値両方更新する場合
      else {
         Query = Query + " SET " + buf_TP_SELL + ", " + buf_SL_SELL;
      }
      // 売り取引全体が更新対象のため、キー項目はstageID, strategyID, symbol, timeframe, orderTypeのみ。ticketは、条件としない。
      Query = Query + " where stageID = " + IntegerToString(mStageID) + " and "+
                      " strategyID = \'" + mStrategyID + "\' and " +
                      " symbol = \'" + mSymbol + "\' and " +
                      " timeframe = " + IntegerToString(mTimeframe) + " and " +
                      " orderType = " + IntegerToString(OP_SELL) + " ;";
   }
   
   // テーブルの更新処理
   if(MySqlExecute(DB, Query) == true) {
 //     printf( "[%d]テスト　売り取引の指値と逆指値の更新成功=%s" , __LINE__ , Query);   
   }
   else {
      printf( "[%d]エラー　売り取引の指値と逆指値の更新失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);              
   }
   
   return true;  //
}//全オーダーの指値と逆指値が設定されていることをチェックする。





//+------------------------------------------------------------------+
//|実行時点のBIDとASKを使って仮想取引の損切を更新する                              |
//|DB版。                                                             |
//|・最小利食値FLOORINGが設定されていれば、損切値の更新を試す                        |
//|・更新対象であるvtradetableのキー項目                                     |
//| stageID, strategyID, symbol, ticket, timeframe, orderTypeのうち、   |
//| ticketとorderTypeは引数とはしない。ticketは使う場面が無いため。orderTypeは       |
//| 関数内で場合分けをして網羅するため。                                        |
//|・実取引と異なり、「ロングの損切は、その時のBID-ストップレベルより小さくなくてはならない。」という制限はない。|
//|・更新により有利な場合にのみ更新する。                                         |
//| ただし、変更後の損切値は、利確値よりも不利であること。                               |
//+------------------------------------------------------------------+
bool DB_v_flooringSL(int mStageID,         // 処理対象とする仮想取引のステージ番号
                     string mStrategyID,   // 処理対象とする仮想取引の戦略名
                     string mSymbol,       // 処理対象とする仮想取引の通貨ペア
                     int    mTimeFrame,    // 処理対象とする仮想取引の時間軸
                     double mPips )  {

   // mPipsが負は想定していない。
   if(mPips < 0)  {
      return false;
   }
   
   string Query = "";
   // 買い取引のFLOORによる逆指値設定用
   if(mPips >= 0)  {
      // 約定値open + 引数mPips*mMarketinfoMODE_POINTが、逆指値orderStopLossよりも大きければ、その値に変更する。
      Query = "update vtradetable SET orderStopLoss = openPrice + " + DoubleToStr(mPips * global_Points, global_Digits);
      Query = Query + " where stageID = " + IntegerToString(mStageID) + " and "+
                      " strategyID = \'" + mStrategyID + "\' and " +
                      " symbol = \'" + mSymbol + "\' and " +
                      " timeframe = " + IntegerToString(mTimeFrame) + " and "+
                      " truncate(openPrice + " + DoubleToStr(mPips * global_Points, global_Digits) + ", " + IntegerToString(global_Digits) + ") > truncate(orderStopLoss, "   + IntegerToString(global_Digits) + ") and " +   // FLOORINGによる損切値が有利になること。
                      " truncate(orderTakeProfit, " + IntegerToString(global_Digits) + ") > truncate(openPrice + " + DoubleToStr(mPips * global_Points, global_Digits) + ", " + IntegerToString(global_Digits) + ") and " + // 利確値の方が、FLOORINGによる損切値より大きいこと。
                      " orderType = " + IntegerToString(OP_BUY) + " ;";      
   }
   // テーブルの更新処理
   if(MySqlExecute(DB, Query) == true) {
 //     printf( "[%d]テスト　FLOORINGによる買い逆指値の更新成功=%s" , __LINE__ , Query);   
   }
   else {
      printf( "[%d]エラー　FLOORINGによる買い逆指値の更新失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);              
   }
   

   // 売り取引のFLOORによる逆指値設定用
   if(mPips >= 0)  {
      // 約定値open - 引数mPips*mMarketinfoMODE_POINTが、逆指値orderStopLossよりも小さければ、その値に変更する。
      Query = "update vtradetable SET orderStopLoss = openPrice - " + DoubleToStr(mPips * global_Points, global_Digits);
      Query = Query + " where stageID = " + IntegerToString(mStageID) + " and "+
                      " strategyID = \'" + mStrategyID + "\' and " +
                      " symbol = \'" + mSymbol + "\' and " +
                      " timeframe = " + IntegerToString(mTimeFrame) + " and "+
                      " truncate(openPrice - " + DoubleToStr(mPips * global_Points, global_Digits) + ", " + IntegerToString(global_Digits) + ") < truncate(orderStopLoss, "   + IntegerToString(global_Digits) + ") and " +   // FLOORINGによる損切値が有利になること。
                      " truncate(orderTakeProfit, " + IntegerToString(global_Digits) + ") < truncate(openPrice - " + DoubleToStr(mPips * global_Points, global_Digits) + ", " + IntegerToString(global_Digits) + ") and " +   // 利確値の方が、FLOORINGによる損切値より小さいこと。
                      " orderType = " + IntegerToString(OP_SELL) + " ;";      
   }
   // テーブルの更新処理
   if(MySqlExecute(DB, Query) == true) {
//      printf( "[%d]テスト　FLOORINGによる売り逆指値の更新成功=%s" , __LINE__ , Query);   
   }
   else {
      printf( "[%d]エラー　FLOORINGによる売り逆指値の更新失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);   
      return false;           
   }

   return true;  //
}


//+------------------------------------------------------------------+
//| 仮想取引の決済をする         |
//+------------------------------------------------------------------+
// 基準日mTargetTime時点での決済損益及び評価損益を計算する。
//
// 【注意】
// この関数は、約定が基準日mTargetTimeに決済がされるかどうかを判断する。
//
// 指定したPIPS数の利益確定TP_PIPS又は損切SL_PIPSを行う。
// 仮想取引st_vOrdersのメンバーのうち、Closeしていない＆openTime = mSettleTimeを決済対象に追加。
// 決済判断にmMarketinfoMODE_BIDやmMarketinfoMODE_ASKではなく、引数mSettlePriceを使う。
// 【注意】約定日がmSettleTime以前の仮想取引を決済対象とするため、mSettleTimeは過去日付から行う必要がある。
bool DB_v_doForcedSettlement(int      mStageID,         // 処理対象とする仮想取引のステージ番号
                             string   mStrategyID, 
                             string   mSymbol,
                             int      mTimeframe, 
                             datetime mTargetTime,   // 決済判定をする基準日。この日時以前の仮想取引に対して、決済する。決済済みの場合は決済損益、それ以外は、評価損益を更新する。                             
                             double   mTP, 
                             double   mSL)  {
   // 約定日が、基準日mTargetTime以前で、通貨ペアのcloseが損切か利確のどちらかを超える取引が決済済み取引
   // 決済日min(pricetable.dt)と決済金額pricetable.close、取引のキー項目はvtradetable.stageID, vtradetable.strategyID, vtradetable.symbol, vtradetable.ticket
   
   string Query = "";
   double mTargetPrice = iClose(mSymbol, mTimeframe, iBarShift(mSymbol, mTimeframe, mTargetTime) ); // 基準時間mTargetTimeのclose値
//printf( "[%d]テスト　決済処理開始 mTargetTime=%d = %s 決済に使う価格=%s" , __LINE__, mTargetTime, TimeToStr(mTargetTime), DoubleToStr(mTargetPrice, global_Digits));   
   
   Query = Query + " SELECT min(pricetable.dt), pricetable.dt_str, pricetable.close,vtradetable.stageID, vtradetable.strategyID, vtradetable.symbol, vtradetable.ticket, vtradetable.timeframe, vtradetable.orderType, vtradetable.openPrice, vtradetable.orderTakeProfit, vtradetable.orderStopLoss ";
   Query = Query + " FROM pricetable, vtradetable ";
   Query = Query + " WHERE ";
   Query = Query + " vtradetable.stageID = " + IntegerToString(mStageID);
   Query = Query + " AND ";
   Query = Query + " vtradetable.strategyID = \'" + mStrategyID + "\' ";
   Query = Query + " AND ";
   Query = Query + " vtradetable.symbol = \'" + mSymbol + "\' ";
   Query = Query + " and ";
   Query = Query + " vtradetable.symbol = pricetable.symbol ";
   Query = Query + " AND ";
   Query = Query + " vtradetable.timeframe = " + IntegerToString(mTimeframe);
   Query = Query + " AND ";
   Query = Query + " pricetable.timeframe = " + IntegerToString(mTimeframe);
   Query = Query + " AND ";
   Query = Query + " vtradetable.closeTime = 0 ";
   Query = Query + " AND ";
   Query = Query + " vtradetable.openTime < " + IntegerToString(mTargetTime); // 計算基準時間mTargetTime以前に約定した取引に限定する。
   Query = Query + " AND ";
   Query = Query + " pricetable.dt <= " + IntegerToString(mTargetTime);  
   Query = Query + " AND ";
   // ↑注意↑
   // Query = Query + " vtradetable.openTime <= pricetable.dt ";
   // としていたが、約定日のcloseで約定したのと同じ時間のcloseで決済することになるため。
   Query = Query + " vtradetable.openTime < pricetable.dt ";
   Query = Query + " AND ";
   Query = Query + " ( ";   // OP_BUYとOP_SELLの場合分けをORでつなぐためのカッコ
   Query = Query + " (vtradetable.orderType = " + IntegerToString(OP_BUY)  + " AND  (vtradetable.orderTakeProfit <= " + DoubleToStr(mTargetPrice, global_Digits) + " OR vtradetable.orderStopLoss >= " + DoubleToStr(mTargetPrice, global_Digits) + " ) )";   
   Query = Query + " OR ";   // OP_BUYとOP_SELLの場合分けをORでつなぐ
   Query = Query + " (vtradetable.orderType = " + IntegerToString(OP_SELL) + " AND  (vtradetable.orderTakeProfit >= " + DoubleToStr(mTargetPrice, global_Digits) + " OR vtradetable.orderStopLoss <= " + DoubleToStr(mTargetPrice, global_Digits) + " ) )";   
   Query = Query + " ) ";   // OP_BUYとOP_SELLの場合分けをORでつなぐためのカッコ
   Query = Query + " GROUP BY vtradetable.stageID, vtradetable.strategyID, vtradetable.symbol, vtradetable.ticket ";
//printf( "[%d]テスト　決済決済対象取引を選択するSQL=%s" , __LINE__, Query);   

   int intCursor = MySqlCursorOpen(DB, Query);
   
   datetime settle_datetime = 0;
   string   settle_datetime_str = "";
   double   settle_close_price = 0.0; // 決済済み取引の決済価格
   int      settle_stageID = 0;
   string   settle_strategyID = "";   
   string   settle_symbol = "";   
   int      settle_ticket = 0;
   int      settle_timeframe = 0;
   int      settle_orderType = 0;        // OP_BUY, OP_SELL   
   double   settle_openPrice = 0.0;      // 約定金額
   double   settle_orderTakeProfit = 0.0;// 利確値。決済金額を1分足のclose値から変更する場合の判断基準に使う。
   double   settle_orderStopLoss = 0.0;  // 損切値。決済金額を1分足のclose値から変更する場合の判断基準に使う。
   int i;
   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);              
   }
   else {
      int Rows = MySqlCursorRows(intCursor);      
      for (i=0; i<Rows; i++) {
         if (MySqlCursorFetchRow(intCursor)) {
            // カーソルの指す1件を取得する。
            // 
            //settle_datetime     = MySqlGetFieldAsInt(intCursor, 0);    // 決済日            → closeTime
            //settle_datetime_str = MySqlGetFieldAsString(intCursor, 1); // 決済日。string型   →  closeTime_str
            // settle_close_price  = MySqlGetFieldAsDouble(intCursor, 2); // 決済済み取引の決済価格 →　closePrice
            settle_close_price  = NormalizeDouble(mTargetPrice, global_Digits); // 決済済み取引の決済価格 →　closePrice
            settle_stageID      = MySqlGetFieldAsInt(intCursor, 3);    // 取引のキー項目
            settle_strategyID   = MySqlGetFieldAsString(intCursor, 4); // 取引のキー項目
            settle_symbol       = MySqlGetFieldAsString(intCursor, 5); // 取引のキー項目
            settle_ticket       = MySqlGetFieldAsInt(intCursor, 6);    // 取引のキー項目
            settle_timeframe    = MySqlGetFieldAsInt(intCursor, 7);    // 取引のキー項目
            settle_orderType    = MySqlGetFieldAsInt(intCursor, 8);    // 取引のキー項目。売買区分。決済損益の計算に使用する。
            settle_openPrice    = MySqlGetFieldAsDouble(intCursor, 9); // 約定金額。決済損益の計算に使用する。
            settle_orderTakeProfit = MySqlGetFieldAsDouble(intCursor, 10); // 約定金額。決済損益の計算に使用する。
            settle_orderStopLoss   = MySqlGetFieldAsDouble(intCursor, 11); // 約定金額。決済損益の計算に使用する。
//printf( "[%d]テスト　tick=%d settle_openPrice=%s" , __LINE__, settle_ticket, DoubleToStr(settle_openPrice, global_Digits));   
            
            //
            // settle_close_priceの見直し
            // closePriceがcloseTimeの終値ではなくなるが、closePriceをTPまたはSPで更新する。これは、FLOORINGの意味がなくなるため。
            // 具体的には、買い取引の場合で、settle_close_price　> TP > SLの場合は、settle_close_priceをTPに更新しないとありえない利益が出る。
            //    一方で、買い取引の場合で、TP > SL > settle_close_priceの場合は、settle_close_priceをSLに更新しないとFLOORIN設定をしても損失が発生する。
            // 前提として、TPとSLは0以上。また、TPとSLが値を持つ場合は、TP>SLとする。
            // 買い取引の場合、
            // TP > 0, SL > 0(つまり、TP > SL)の場合で、
            //    settle_close_price　>= TP > SLの場合は、settle_close_price　=　TPに更新する
            //    TP > SL >= settle_close_priceの場合は、settle_close_price　=　SLに更新する
            // TP = 0, SL > 0（つまり、TP未設定）の場合で、
            //    settle_close_price > SLの場合は、更新無し。
            //    settle_close_price <= SLの場合は、settle_close_price = SLに更新する。
            // TP > 0, SL = 0（つまり、SL未設定）の場合で、
            //    settle_close_price >= TPの場合は、settle_close_price = TPに更新する。
            //    TP > settle_close_priceの場合は、更新無し。
            // TP = 0, SL = 0の場合は、更新無し。
            //
            // 売り取引の場合、
            // TP > 0, SL > 0(つまり、TP < SL)の場合で、
            //    settle_close_price　<= TP < SLの場合は、settle_close_price　=　TPに更新する
            //    TP < SL <= settle_close_priceの場合は、settle_close_price　=　SLに更新する
            // TP = 0, SL > 0（つまり、TP未設定）の場合で、
            //    settle_close_price < SLの場合は、更新無し。
            //    settle_close_price >= SLの場合は、settle_close_price = SLに更新する。
            // TP > 0, SL = 0（つまり、SL未設定）の場合で、
            //    settle_close_price <= TPの場合は、settle_close_price = TPに更新する。
            //    TP < settle_close_priceの場合は、更新無し。
            // TP = 0, SL = 0の場合は、更新無し。
            if(settle_orderType == OP_BUY) {
               if(settle_orderTakeProfit > 0.0 && settle_orderStopLoss > 0.0) {
                  if(NormalizeDouble(settle_close_price, global_Digits) >= NormalizeDouble(settle_orderTakeProfit, global_Digits) ) {
                     settle_datetime = mTargetTime;
                     settle_datetime_str = TimeToStr(mTargetTime);
                     settle_close_price = NormalizeDouble(settle_orderTakeProfit, global_Digits);

printf( "[%d]テスト　約定金額=%sロングで、決済候補の金額=%s > 利確値=%sのため、利確した" , __LINE__, 
                DoubleToStr(settle_openPrice, global_Digits),
                DoubleToStr(settle_close_price, global_Digits),
                DoubleToStr(settle_orderTakeProfit, global_Digits));
printf( "[%d]テスト　ステージ番号=%d チケット番号=%d　約定金額=%s 利確=%s 損切=%s" , __LINE__, settle_stageID, settle_ticket, 
                     DoubleToStr(settle_openPrice, global_Digits), 
                     DoubleToStr(settle_orderTakeProfit, global_Digits),
                     DoubleToStr(settle_orderStopLoss, global_Digits));
                
                     
                  } 
                  else if(NormalizeDouble(settle_close_price, global_Digits) <= NormalizeDouble(settle_orderStopLoss, global_Digits) ) {

                     settle_datetime = mTargetTime;
                     settle_datetime_str = TimeToStr(mTargetTime);
                     settle_close_price = NormalizeDouble(settle_orderStopLoss, global_Digits);
                  }
               }
               else if(settle_orderTakeProfit == 0.0 && settle_orderStopLoss > 0.0) {
                  if(NormalizeDouble(settle_close_price, global_Digits) >= NormalizeDouble(settle_orderStopLoss, global_Digits) ) {
                     // 何もしない
                  } 
                  else if(NormalizeDouble(settle_close_price, global_Digits) <= NormalizeDouble(settle_orderStopLoss, global_Digits) ) {
                     settle_datetime = mTargetTime;
                     settle_datetime_str = TimeToStr(mTargetTime);
                     settle_close_price = NormalizeDouble(settle_orderStopLoss, global_Digits);
                  }
               }
               else if(settle_orderTakeProfit > 0.0 && settle_orderStopLoss == 0.0) {
                  if(NormalizeDouble(settle_close_price, global_Digits) >= NormalizeDouble(settle_orderTakeProfit, global_Digits) ) {
                     settle_datetime = mTargetTime;
                     settle_datetime_str = TimeToStr(mTargetTime);
                     settle_close_price = NormalizeDouble(settle_orderTakeProfit, global_Digits);
                  } 
                  else if(NormalizeDouble(settle_close_price, global_Digits) <= NormalizeDouble(settle_orderStopLoss, global_Digits) ) {
                     // 何もしない
                  }
               }
               else if(settle_orderTakeProfit == 0.0 && settle_orderStopLoss == 0.0) {
                  // 何もしない               
               }
               else if(settle_orderTakeProfit == 0.0 && settle_orderStopLoss == 0.0) {
                  // 何もしない               
               }
            }
            else if(settle_orderType == OP_SELL){
               if(settle_orderTakeProfit > 0.0 && settle_orderStopLoss > 0.0) {            
                  if(NormalizeDouble(settle_close_price, global_Digits) <= NormalizeDouble(settle_orderTakeProfit, global_Digits) ) {
                     settle_datetime = mTargetTime;
                     settle_datetime_str = TimeToStr(mTargetTime);
                     settle_close_price = NormalizeDouble(settle_orderTakeProfit, global_Digits);
                  } 
                  else if(NormalizeDouble(settle_close_price, global_Digits) >= NormalizeDouble(settle_orderStopLoss, global_Digits) ) {
                     settle_datetime = mTargetTime;
                     settle_datetime_str = TimeToStr(mTargetTime);
                     settle_close_price = NormalizeDouble(settle_orderStopLoss, global_Digits);
                  }
               }
               else if(settle_orderTakeProfit == 0.0 && settle_orderStopLoss > 0.0) {
                  if(NormalizeDouble(settle_close_price, global_Digits) <= NormalizeDouble(settle_orderStopLoss, global_Digits) ) {
                     // 何もしない
                  } 
                  else if(NormalizeDouble(settle_close_price, global_Digits) >= NormalizeDouble(settle_orderStopLoss, global_Digits) ) {
                     settle_datetime = mTargetTime;
                     settle_datetime_str = TimeToStr(mTargetTime);
                     settle_close_price = NormalizeDouble(settle_orderStopLoss, global_Digits);
                  }
               }
               else if(settle_orderTakeProfit > 0.0 && settle_orderStopLoss == 0.0) {
                  if(NormalizeDouble(settle_close_price, global_Digits) <= NormalizeDouble(settle_orderTakeProfit, global_Digits) ) {
                     settle_datetime = mTargetTime;
                     settle_datetime_str = TimeToStr(mTargetTime);
                     settle_close_price = NormalizeDouble(settle_orderTakeProfit, global_Digits);
                  } 
                  else if(NormalizeDouble(settle_close_price, global_Digits) >= NormalizeDouble(settle_orderStopLoss, global_Digits) ) {
                     // 何もしない
                  }            
               }
               else if(settle_orderTakeProfit == 0.0 && settle_orderStopLoss == 0.0) {
                  // 何もしない               
               }
               
            }


            
            double settle_PL = 0.0; // → closePL
            if(settle_orderType == OP_BUY) {
               settle_PL = NormalizeDouble( (settle_close_price - settle_openPrice) / global_Points, global_Digits); // 決済損益(pips)
            }
            else if(settle_orderType == OP_SELL) {
               settle_PL = NormalizeDouble(  (-1.0) * (settle_close_price - settle_openPrice) / global_Points, global_Digits); // 決済損益(pips)
            }
            /*
printf( "[%d]テスト　決済基準時間=%s" , __LINE__, TimeToStr(mTargetTime));   
printf( "[%d]テスト　決済日=%d = %s" , __LINE__, settle_datetime, settle_datetime_str);   
printf( "[%d]テスト　決済価格=%s 約定金額=%s　損益=%s" , __LINE__, DoubleToStr(settle_close_price), DoubleToStr(settle_openPrice), DoubleToStr(settle_PL, global_Digits));   
printf( "[%d]テスト　stage=%d strategy=%s 通貨=%s tick=%d 売買=%d" , __LINE__, settle_stageID, settle_strategyID, settle_symbol,settle_ticket, settle_orderType);
            */
           
            //　vtradetableテーブルを更新する。
            string Query_updatevTrade = "";
            Query_updatevTrade = Query_updatevTrade + " update vtradetable ";     
            Query_updatevTrade = Query_updatevTrade + " set closeTime = " + IntegerToString(settle_datetime) + ", closeTime_str = \'" + settle_datetime_str + "\', closePrice = " + DoubleToStr(settle_close_price, global_Digits) + ", closePL = " + DoubleToStr(settle_PL, global_Digits) + " ";     
            Query_updatevTrade = Query_updatevTrade + " where stageID = " + IntegerToString(settle_stageID);    
            Query_updatevTrade = Query_updatevTrade + " AND " ;
            Query_updatevTrade = Query_updatevTrade + " strategyID = \'" + settle_strategyID + "\' ";
            Query_updatevTrade = Query_updatevTrade + " AND " ;
            Query_updatevTrade = Query_updatevTrade + " symbol = \'" + settle_symbol + "\' ";
            Query_updatevTrade = Query_updatevTrade + " AND " ;
            Query_updatevTrade = Query_updatevTrade + " ticket = " + IntegerToString(settle_ticket);
            Query_updatevTrade = Query_updatevTrade + " AND " ;
            Query_updatevTrade = Query_updatevTrade + " timeframe = " + IntegerToString(mTimeframe);
            Query_updatevTrade = Query_updatevTrade + " AND " ;
            Query_updatevTrade = Query_updatevTrade + " orderType = " + IntegerToString(settle_orderType) + "; ";   
//printf( "[%d]テスト　決済処理中:%s" , __LINE__, Query_updatevTrade);   
            // テーブルの更新処理
            if(MySqlExecute(DB, Query_updatevTrade) == true) {
//               printf( "[%d]テスト　決済損益の更新成功=%s" , __LINE__ , Query_updatevTrade);   
            }
            else {
               printf( "[%d]エラー　決済損益の更新失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query_updatevTrade);              
            }
//printf( "[%d]テスト　決済処理中" , __LINE__);   
         }
      }
   }      // else 
   MySqlCursorClose(intCursor);
//printf( "[%d]テスト　決済処理終了" , __LINE__);   
   

   // 
   // 決済損益の計算はここまで。
   // 

   // 
   // 約定日が、mTargetTime以前であって未決済の取引は、mTargetTimeのclose（=estimate_price)で評価損益を計算する。
   // 売りと買いでupdate文を分けて実行する
   // 
   double estimatePrice = iClose(mSymbol, global_Period4vTrade, iBarShift(mSymbol,global_Period4vTrade,mTargetTime)); // 評価損益を計算する基準時間mTargetTimeのcloseを評価値とする。
   string Query_est = "";
/*printf( "[%d]テスト　評価損益に使うclose=%s シフト=%d = %s" , __LINE__, DoubleToStr(estimatePrice, global_Digits),
                   iBarShift(mSymbol,global_Period4vTrade,mTargetTime), TimeToStr(mTargetTime)  );      */

   // 買い取引の評価損益更新
   // orderType = OP_BUYであれば、set estimatePL = truncate((estimatePrice - openPrice) / global_Pointsの値, global_Digitsの値)
   Query_est = "";
   Query_est = Query_est + " update vtradetable ";
   Query_est = Query_est + " set estimatePL = (truncate(" + DoubleToStr(estimatePrice, global_Digits) + ", 5) - truncate(openPrice, 5)) / " + DoubleToStr(global_Points, global_Digits) + " , ";
  // Query_est = Query_est + " set estimatePL = truncate(" + DoubleToStr(estimatePrice, global_Digits) + ", 5) / " + DoubleToStr(global_Points, global_Digits) + " - truncate(openPrice, 5) / " + DoubleToStr(global_Points, global_Digits) + " , ";
   Query_est = Query_est +     " estimatePrice = truncate(" + DoubleToStr(estimatePrice, global_Digits) + ", " + IntegerToString(global_Digits) + "), ";
   Query_est = Query_est +     " estimateTime  = " + IntegerToString(mTargetTime) + ", ";
   Query_est = Query_est +     " estimateTime_str = \'" + TimeToStr(mTargetTime) + "\'";   
   Query_est = Query_est + " where ";
   Query_est = Query_est + " (stageID, strategyID, symbol, ticket, timeframe, orderType) = "; // キー項目の列挙   
   // 約定日が、mTargetTime以前であって未決済の取引のキー項目を選択する副問い合わせ
   // （参考資料）https://atmarkit.itmedia.co.jp/ait/articles/1208/06/news118.html
   Query_est = Query_est + "  ANY(SELECT * FROM (select stageID, strategyID, symbol, ticket, timeframe, orderType from vtradetable "; 
   // ↑MYSQLは副問い合わせで同じテーブルを参照できない＝http://doshiroutonike.com/web/other-web/2778
   Query_est = Query_est +    " where ";
   Query_est = Query_est +    " stageID = " + IntegerToString(mStageID);
   Query_est = Query_est +    " AND ";
   Query_est = Query_est +    " strategyID = \'" + mStrategyID + "\' ";
   Query_est = Query_est +    " AND ";
   Query_est = Query_est +    " symbol = \'" + mSymbol + "\'";
   Query_est = Query_est +    " AND ";
   Query_est = Query_est +    " timeframe = " + IntegerToString(mTimeframe);
   Query_est = Query_est +    " AND " ;
   Query_est = Query_est +    " orderType = " + IntegerToString(OP_BUY);   
   Query_est = Query_est +    " AND " ;
   Query_est = Query_est +    " openTime <= " + IntegerToString(mTargetTime);   // 計算基準時間mTargetTime以前に約定した取引に限定する。
   Query_est = Query_est +    " AND " ;
   Query_est = Query_est +    " closeTime <= 0 ";                           // 未決済取引に限定する。
   Query_est = Query_est +    ") AS temp1);";
//printf( "[%d]テスト　" , __LINE__);      
   if(MySqlExecute(DB, Query_est) == true) {
//      printf( "[%d]テスト　買いの評価損益の更新成功=%s" , __LINE__ , Query_est);   
   }
   else {
      printf( "[%d]エラー　買いの評価の更新失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query_est);              
   }
//printf( "[%d]テスト　" , __LINE__);   
   // 売り取引の評価損益更新
   // orderType = OP_SELLであれば、set estimatePL = truncate((-1.0) * ((estimate_priceの値 - openPrice) / global_Pointsの値), global_Digitsの値)   
   Query_est = "";
   Query_est = Query_est + " update vtradetable ";
   Query_est = Query_est + " set estimatePL = (-1.0) * (truncate(" + DoubleToStr(estimatePrice, global_Digits) + ", 5) - truncate(openPrice, 5)) / " + DoubleToStr(global_Points, global_Digits) + " , ";
   Query_est = Query_est +     " estimatePrice = truncate(" + DoubleToStr(estimatePrice, global_Digits) + ", " + IntegerToString(global_Digits) + "), ";
   Query_est = Query_est +     " estimateTime  = " + IntegerToString(mTargetTime) + ", ";
   Query_est = Query_est +     " estimateTime_str = \'" + TimeToStr(mTargetTime) + "\'";   
   Query_est = Query_est + " where ";
   Query_est = Query_est + " (stageID, strategyID, symbol, ticket, timeframe, orderType) = "; // キー項目の列挙   
   // 約定日が、mTargetTime以前であって未決済の取引のキー項目を選択する副問い合わせ
   // （参考資料）https://atmarkit.itmedia.co.jp/ait/articles/1208/06/news118.html
   Query_est = Query_est + "  ANY(SELECT * FROM (select stageID, strategyID, symbol, ticket, timeframe, orderType from vtradetable "; 
   Query_est = Query_est +    " where ";
   Query_est = Query_est +    " stageID = " + IntegerToString(mStageID);
   Query_est = Query_est +    " AND ";
   Query_est = Query_est +    " strategyID = \'" + mStrategyID + "\' ";
   Query_est = Query_est +    " AND ";
   Query_est = Query_est +    " symbol = \'" + mSymbol + "\' ";
   Query_est = Query_est +    " AND ";
   Query_est = Query_est +    " timeframe = " + IntegerToString(mTimeframe);
   Query_est = Query_est +    " AND " ;
   Query_est = Query_est +    " orderType = " + IntegerToString(OP_SELL);   
   Query_est = Query_est +    " AND " ;
   Query_est = Query_est +    " openTime <= " + IntegerToString(mTargetTime);   // 計算基準時間mTargetTime以前に約定した取引に限定する。
   Query_est = Query_est +    " AND " ;
   Query_est = Query_est +    " closeTime <= 0 ";                           // 未決済取引に限定する。
   Query_est = Query_est +    ") AS temp1);";
   // テーブルの更新処理
//printf( "[%d]テスト　" , __LINE__);      
   
   if(MySqlExecute(DB, Query_est) == true) {
//      printf( "[%d]テスト　売りの評価の更新成功=%s" , __LINE__ , Query_est);   
   }
   else {
      printf( "[%d]エラー　売りの評価の更新失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query_est);              
   }
//printf( "[%d]テスト　" , __LINE__);      
   
   return true;
}                                 


//+-------------------------------------------------------------------------------------------------------------+
//| 仮想取引を評価し、戦略別・通貨ペア別・タイムフレーム別・売買区分別・損益別の各指標の平均と偏差を計算する。  |
//| DB対応版。呼び出している4つの関数名の変更のみ。                                                             |
//| ※評価対象となる仮想取引は、約定時間が第6引数mFROM_vOrder_openTimeからmAnalyzeTimeにオープンしたものに限る。|
//+-------------------------------------------------------------------------------------------------------------+
// 4つの計算のうち、4つ全滅失敗したら、falseを返す。
bool DB_create_st_vAnalyzedIndex(
                     int      mStageID,                // 入力：使用する取引の絞り込み要素。どのステージの取引を使うか
                     string   mStrategyID,             // 入力：使用する取引の絞り込み要素
                     string   mSymbol,                 // 入力：使用する取引の絞り込み要素
                     int      mTimeframe_calc,         // 入力：PERIOD_M15。指標を計算する時に使う時間軸
                     datetime mAnalyzeTime,            // 入力：平均、偏差を計算する基準時間＝指標の平均と偏差を計算の終了時間。
                     datetime mFROM_vOrder_openTime) { // 入力：指標の平均と偏差を計算の開始時間(datetime型)
   if(mFROM_vOrder_openTime > mAnalyzeTime) {
      printf( "[%d]テスト 計算対象取引の先頭時間%d:%sが末尾時間%d:%sより大きい" , __LINE__,
                mFROM_vOrder_openTime, TimeToStr(mFROM_vOrder_openTime),
                 mAnalyzeTime, TimeToStr(mAnalyzeTime));
      return false;
   }
   //
   //
   // 仮想取引全てを、買い＋利益、買い＋損失、売り＋利益、売り＋損失の4つに分類して、
   // それぞれの指標データの平均と偏差をグローバル変数に格納する。
   //
   //
   bool mFlag = false;
   bool ret = false; // 初期値をfalseとし、4指標のうち1つでも正常終了すればtrueに変わる。つまり、全滅を逃れる。 

   // st_vAnalyzedIndexesBUY_Profit, st_vAnalyzedIndexesBUY_Loss, 
   // st_vAnalyzedIndexesSELL_Profit, st_vAnalyzedIndexesSELL_Lossを
   // 4指標の全てを初期化する。
   initALL_vMeanSigma(); 

   // 仮想取引を評価し、戦略別・通貨ペア別・タイムフレーム別・売買区分別・損益別の各指標の平均と偏差を計算する。 
   //
   // 買い　かつ　利益の取引を使った各指標の平均と偏差を計算
   //
   mFlag = DB_create_Stoc_vOrdersBUY_PROFIT(mStageID,               // 入力：計算対象にする取引のステージ番号 
                                            mStrategyID,            // 入力：計算中の戦略名 
                                            mSymbol,                // 入力：計算中の通貨ペア 
                                            mTimeframe_calc,        // 入力：どの時間軸で計算した指標を使うか。PERIOD_M1～PERIOD_MN1 
                                            mAnalyzeTime,           // 入力：計算基準時間。評価対象となる仮想取引の約定時間がこの値まで。
                                            mFROM_vOrder_openTime); // 入力：評価対象となる仮想取引の約定時間がこの値以降。
   if(mFlag == false) {
      printf("[%d]テスト DB_create_Stoc_vOrdersBUY_PROFIT失敗", __LINE__);
   }
   else {
      ret = true;
   }


//printf("[%d]テスト ステージ>%d<のデータを使って4種の平均、偏差を計算する。", __LINE__, mStageID);

   //
   // 買い　かつ　損失の取引を使った各指標の平均と偏差を計算
   //
   mFlag = DB_create_Stoc_vOrdersBUY_LOSS(mStageID,               // 入力：計算中のステージ番号 
                                          mStrategyID,            // 入力：計算中の戦略名 
                                          mSymbol,                // 入力：計算中の通貨ペア 
                                          mTimeframe_calc,        // 入力：どの時間軸で計算した指標を使うか。PERIOD_M1～PERIOD_MN1 
                                          mAnalyzeTime,           // 入力：計算基準時間 
                                          mFROM_vOrder_openTime); // 入力：評価対象となる仮想取引の約定時間がこの値以降。
   if(mFlag == false) {
      printf("[%d]テスト DB_create_Stoc_vOrdersBUY_LOSS失敗", __LINE__);
   }
   else {
      ret = true;
   }

  

   //
   // 売り　かつ　利益の取引を使った各指標の平均と偏差を計算
   //
   mFlag = DB_create_Stoc_vOrdersSELL_PROFIT(mStageID,               // 入力：計算中のステージ番号 
                                             mStrategyID,            // 入力：計算中の戦略名 
                                             mSymbol,                // 入力：計算中の通貨ペア 
                                             mTimeframe_calc,        // 入力：どの時間軸で計算した指標を使うか。PERIOD_M1～PERIOD_MN1 
                                             mAnalyzeTime,           // 入力：計算基準時間 
                                             mFROM_vOrder_openTime); // 入力：評価対象となる仮想取引の約定時間がこの値以降。
   if(mFlag == false) {
      printf("[%d]テスト DB_create_Stoc_vOrdersSELL_PROFIT失敗", __LINE__);
   }
   else {
      ret = true;
   }



   //
   // 売り　かつ　損失の取引を使った各指標の平均と偏差を計算
   //
   mFlag = DB_create_Stoc_vOrdersSELL_LOSS(mStageID,               // 入力：計算中のステージ番号 
                                           mStrategyID,            // 入力：計算中の戦略名 
                                           mSymbol,                // 入力：計算中の通貨ペア 
                                           mTimeframe_calc,        // 入力：どの時間軸で計算した指標を使うか。PERIOD_M1～PERIOD_MN1 
                                           mAnalyzeTime,           // 入力：計算基準時間 
                                           mFROM_vOrder_openTime); // 入力：評価対象となる仮想取引の約定時間がこの値以降。
   if(mFlag == false) {
      printf("[%d]テスト DB_create_Stoc_vOrdersSELL_LOSS失敗", __LINE__);
   }
   else {
      ret = true;
   }



   if(ret == false) {
       printf("[%d]テスト DB_create_Stoc_vOrdersは、4つ全滅", __LINE__);
       return false;
   }
   else {
      st_vAnalyzedIndex dummy;
      init_st_vAnalyzedIndexes(dummy);
      DB_insert_st_vAnalyzedIndexes(true, dummy);  // trueにより、バッファの利用状況によらず、DB書き出し。
                                                // dummyは、空値の代替 
      return true;
   }


   return ret;
}



//+-----------------------------------------------------------------------------+
//| create_Stoc_vOrdersBUY_PROFITのDB対応版。
//+-----------------------------------------------------------------------------+
// 仮想取引を評価し、戦略別・通貨ペア別・タイムフレーム別・売買区分別・損益別の各指標の平均と偏差を計算する。
// 約定日が、引数mFROM_vOrder_openTimeから、mCalcTimeまでの約定とそれに紐づく指標データを平均、偏差の計算処理対象とする。
// 仮想取引が買い＋利益である時の指標の平均と偏差を計算する。
// 計算結果は、グローバル変数st_vAnalyzedIndexesBUY_Profitに入る。
bool DB_create_Stoc_vOrdersBUY_PROFIT(int      mStageID,              // 入力：計算中のステージ番号
                                      string   mStrategyID,           // 入力：計算中の戦略名
                                      string   mSymbol,               // 入力：計算中の通貨ペア
                                      int      mTimeframe_calc,       // 入力：PERIOD_M15。指標を計算する時に使う時間軸
                                      datetime mCalcTime,             // 入力：計算基準時間。評価対象となる仮想取引の約定時間がこの時間まで。
                                      datetime mFROM_vOrder_openTime  // 入力：評価対象となる仮想取引の約定時間がこの値以降。
                                     ) {
   // 対象とする最初の時間が負の場合は、仮想取引の先頭から計算対象とする。
   if(mFROM_vOrder_openTime < 0) {
      mFROM_vOrder_openTime = 0;
   }

   if(mFROM_vOrder_openTime > mCalcTime) {
      printf( "[%d]テスト 計算対象取引の先頭時間%d:%sが末尾時間%d:%sより大きい" , __LINE__,
                mFROM_vOrder_openTime, TimeToStr(mFROM_vOrder_openTime),
                 mCalcTime, TimeToStr(mCalcTime));
      return false;
   }

   // キー項目の初期値を設定する
   st_vAnalyzedIndexesBUY_Profit.stageID     = mStageID;
   st_vAnalyzedIndexesBUY_Profit.strategyID  = mStrategyID;
   st_vAnalyzedIndexesBUY_Profit.symbol      = mSymbol;
   st_vAnalyzedIndexesBUY_Profit.timeframe   = mTimeframe_calc;
   st_vAnalyzedIndexesBUY_Profit.orderType   = OP_BUY;
   st_vAnalyzedIndexesBUY_Profit.PLFlag      = vPROFIT; // vPL_DEFAULT=0, vPROFIT=1, vLOSS=-1
   st_vAnalyzedIndexesBUY_Profit.analyzeTime = mCalcTime;
    
   // 4種のどのパターンで処理をするか。
   int BS_PL_FLAG = vBUY_PROFIT;

   if(StringLen(mStrategyID) <= 0) {
printf( "[%d]テスト 戦略名未設定" , __LINE__);
      return false;
   }
   if(StringLen(mSymbol) <= 0) {
printf( "[%d]テスト 通貨ペア未設定" , __LINE__);
      return false;
   }
   if(mTimeframe_calc < 0) {
printf( "[%d]テスト 時間軸未設定" , __LINE__);   
      return false;
   }


   int    Index_of_st_vOrderIndexes = -1;
   double indexMean  = 0.0;
   double indexSigma = 0.0;

   bool retFlag = false;  
   int    DB_MEAN_SIGMA_Num = 0;
   double DB_MEAN_SIGMA_Data[DB_VTRADENUM_MAX];
      
  //
  // １．買い　かつ　利益の仮想取引のオープン時各指標値は、ここから。
  //
  // 変数の初期化。平均と偏差を計算するための配列MA_GC_mData[i]などを初期化。
   DB_MEAN_SIGMA_Num = 0;
   ArrayInitialize(DB_MEAN_SIGMA_Data, 0.0);


   //    
   // ①買いかつ利益の仮想取引を検索する　→　副問い合わせtmpTableファイルに格納する。　　←　基準時間に近い約定ほど重みづけしたり、最近の数％件数のみを対象とするなど、工夫する。
   //  stageID　= mStadeID , strategyID = mStrategyID , symbol = mSymbol
   //  openTime < mCalcTime // openTime = mCalcTimeの取引は、決済損益も評価損益も0となるため。
   //  openType = OP_BUY
   //  (closeTime > 0 AND closeTime < mCalcTime AND closePL > 0) // 決済損益が正。　closeTime < mCalcTimeは、上記openTime < mCalcTimeで満たすが念のため、追加。
   //  (closeTime = 0 AND estimateTime > 0 AND estimateTime < mCalcTime AND estimatePL > 0) // 評価損益が正。　closeTime < mCalcTimeは、上記openTime < mCalcTimeで満たすが念のため、追加。
   string Query = "";

   Query = Query + " SELECT symbol, openTime FROM vtradetable ";
   Query = Query + " where ";
   Query = Query + " stageID = " + IntegerToString(mStageID);
   Query = Query + " AND ";
   Query = Query + " strategyID = \'" + mStrategyID + "\'" ;
   Query = Query + " AND " ;
   Query = Query + " symbol = \'" + mSymbol + "\'" ;
   Query = Query + " AND "; 
   Query = Query + " orderType = " + IntegerToString(OP_BUY) ;
   Query = Query + " AND ( " ;
   // 約定日が、引数mFROM_vOrder_openTimeから、mCalcTimeまでの約定とそれに紐づく指標データを平均、偏差の計算処理対象とする。
   Query = Query + " ( (openTime >= " + IntegerToString(mFROM_vOrder_openTime) + " AND openTime <= " + IntegerToString(mCalcTime) + ") " ;
   Query = Query + "AND " ;

   // 決済損益の計算対象取引は、決済日closeTimeがmFROM_vOrder_openTimeとmCalcTimeの間にあること。決済損益closePL > 0.0であること。
   Query = Query + "(closeTime >= " + IntegerToString(mFROM_vOrder_openTime) + " AND closeTime <= " + IntegerToString(mCalcTime) + ") AND closePL > 0.0)";
   Query = Query + " OR ";
   // 評価損益の計算対象取引は、決済日が0のままか、決済されていたとしても決済日closeTimeがmTO_vOrder_openTimeよりあとであること。評価日estimateTimeがmCalcTimeと同じかそれより前。決済損益closePL > 0.0であること。
   Query = Query + "( (estimateTime > 0 AND estimateTime <= " + IntegerToString(mCalcTime) + ") AND (closeTime = 0 OR closeTime > " + IntegerToString(mCalcTime) + ") AND estimatePL > 0.0))";

//   string sqlGetIndexBuyProfit_Query = Query;
   // [サンプル]
// printf("[%d]テスト 確認用%s" , __LINE__, Query);

   // ②副問い合わせの戻り値Symbol, openTime(, timeframeは引数timeframeを使う）をキー項目として、平均と偏差の計算対象とする指標データを検索する。
   //  なお、indextable.calc_dtを使って降順に並び変えておく。計算対象がDB_VTRADENUM_MAX件以上になったとしても、影響力が大きいとみなせる最近の指標データを計算対象にできるため。
   // →上記①で求めた副問い合わせの前後に、indextableの検索をする部品を追加する。
   string preQuery = "";   
   preQuery = preQuery + " SELECT * FROM indextable ";
   preQuery = preQuery + " WHERE ";
   preQuery = preQuery + " timeframe = "+ IntegerToString(mTimeframe_calc);
   preQuery = preQuery + " AND ";
   preQuery = preQuery + " (symbol, calc_dt) = ";
   preQuery = preQuery + " ANY(SELECT * FROM ( ";


   //
   // indextable検索用部品preQueryに、副問い合わせQueryに結合する
   Query = preQuery + Query;   
   //
   // 副問い合わせの末尾を結合
   Query = Query + " ) AS temp1) ORDER BY calc_dt DESC;";

/*
   sqlGetIndexBuyProfit = "";
   sqlGetIndexBuyProfit = sqlGetIndexBuyProfit + " SELECT " + IntegerToString(mStageID) + ", " + IntegerToString(OP_BUY) + ", " + IntegerToString(vPROFIT) + ", * FROM indextable ";
   sqlGetIndexBuyProfit = sqlGetIndexBuyProfit + " WHERE ";
   sqlGetIndexBuyProfit = sqlGetIndexBuyProfit + " timeframe = "+ IntegerToString(mTimeframe_calc);
   sqlGetIndexBuyProfit = sqlGetIndexBuyProfit + " AND ";
   sqlGetIndexBuyProfit = sqlGetIndexBuyProfit + " (symbol, calc_dt) = ";
   sqlGetIndexBuyProfit = sqlGetIndexBuyProfit + " ANY(SELECT * FROM ( ";
   sqlGetIndexBuyProfit = sqlGetIndexBuyProfit + Query + " ) AS temp1) ORDER BY calc_dt DESC;";
*/
//   printf("[%d]テスト 実験中BUY_PROFITな仮想取引の約定時間におけるindexを検索：sqlGetIndexBuyProfit=%s" , __LINE__, sqlGetIndexBuyProfit);
//   printf("[%d]テスト 実験中BUY_PROFITな仮想取引の約定時間におけるindexを検索：Query=%s" , __LINE__, Query);

   int i;
   string buf_symbol = "";
   int    buf_timeframe = 0;
   int    buf_calc_dt = 0;
   string buf_calc_dt_str = "";
   
   int    buf_read_integer = 0;
   double buf_read_double  = 0.0;
   int    countSatisfy    = 0; // satisfyGeneralRules関数で条件を満たしたindexテーブルの個数
   int    countSatisfyMAX = 0; // satisfyGeneralRules関数の判定対象としてindexテーブルの総数

   init_Mean_Sig_Variables();  // 平均、偏差を計算するためのデータを格納する配列及びデータ個数を示す変数を初期化する。
   int intCursor = MySqlCursorOpen(DB, Query);

   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);              
   }
   else {
      int Rows = MySqlCursorRows(intCursor);
//printf( "[%d]テスト　計算基準時間%sのBUY_PROFITに該当する取引の約定時間におけるindex件数:%d件%s" , __LINE__, TimeToStr(mCalcTime), Rows, Query);              

      st_vOrderIndex buf_st_vOrderIndex;   // indextableテーブルから1行読み込んだデータを一時的に保存する。
      countSatisfyMAX = Rows;    // BUY_PROFITに該当する取引の約定時間におけるindex件数。かつ、satisfyGeneralRules関数による絞り込み前のindex件数。
      countSatisfy    = 0;       // satisfyGeneralRules関数による絞り込み通過件数を0で初期化。
      for (i = 0; i < Rows; i++) {
         // DBから読み込んだ1件の指標データを一時的に変数に格納する。
         
         init_st_vOrderIndex(buf_st_vOrderIndex);// 一時的に値を格納する変数の初期化。

         if (MySqlCursorFetchRow(intCursor)) {
            // カーソルの指す1件を取得する。
            // 
            buf_st_vOrderIndex.symbol      = MySqlGetFieldAsString(intCursor, 0);
            buf_st_vOrderIndex.timeframe   = MySqlGetFieldAsInt(intCursor,    1);
            buf_st_vOrderIndex.calcTime    = MySqlGetFieldAsInt(intCursor,    2);
            buf_calc_dt_str = MySqlGetFieldAsString(intCursor, 3);
            
            buf_read_integer = MySqlGetFieldAsInt(intCursor, 4);
            buf_st_vOrderIndex.MA_GC = buf_read_integer;

            buf_read_integer = MySqlGetFieldAsInt(intCursor, 5);
            buf_st_vOrderIndex.MA_DC = buf_read_integer;

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 6);
            buf_st_vOrderIndex.MA_Slope5 = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 7);
            buf_st_vOrderIndex.MA_Slope25 = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 8);
            buf_st_vOrderIndex.MA_Slope75 = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 9);
            buf_st_vOrderIndex.BB_Width = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,10);
            buf_st_vOrderIndex.IK_TEN = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,11);
            buf_st_vOrderIndex.IK_CHI = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,12);
            buf_st_vOrderIndex.IK_LEG = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_integer = MySqlGetFieldAsInt(intCursor,13);
            buf_st_vOrderIndex.MACD_GC = buf_read_integer;

            buf_read_integer = MySqlGetFieldAsInt(intCursor,14);
            buf_st_vOrderIndex.MACD_DC = buf_read_integer;

            buf_read_double =  MySqlGetFieldAsInt(intCursor,15);
            buf_st_vOrderIndex.RSI_VAL= NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,16);
            buf_st_vOrderIndex.STOC_VAL= NormalizeDouble(buf_read_double, global_Digits);

            buf_read_integer = MySqlGetFieldAsInt(intCursor,17);
            buf_st_vOrderIndex.STOC_GC = buf_read_integer;

            buf_read_integer = MySqlGetFieldAsInt(intCursor,18);
            buf_st_vOrderIndex.STOC_DC = buf_read_integer;

            buf_read_double =  MySqlGetFieldAsInt(intCursor,19);
            buf_st_vOrderIndex.RCI_VAL= NormalizeDouble(buf_read_double, global_Digits);


            // satisfyGeneralRules関数を使って、読みだしたindextableテーブルデータがルールを満たしているかを確認し、
            // 条件を満たしていなければ、廃棄する。
            bool flag_satisfyGeneralRules = satisfyGeneralRules(buf_st_vOrderIndex, BS_PL_FLAG);
            if(flag_satisfyGeneralRules == false) {
               // 条件を満たさなかった時は、何もしない               
            }
            else {
               countSatisfy++; // satisfyGeneralRules関数を使った絞り込みを通過した件数を1増やす。

               // ルールを満たした指標（BUY/PROFIT等の条件を満たした取引を約定したときの指標）のため、
               // 各項目の値を平均、偏差計算用配列にコピーする。
               if(buf_st_vOrderIndex.MA_GC > INT_VALUE_MIN) {
                  DB_MA_GC_mData[DB_MA_GC_mDataNum] = buf_st_vOrderIndex.MA_GC;
                  DB_MA_GC_mDataNum++;
               }

               if(buf_st_vOrderIndex.MA_DC > INT_VALUE_MIN) {
                  DB_MA_DC_mData[DB_MA_DC_mDataNum] = buf_st_vOrderIndex.MA_DC;
                  DB_MA_DC_mDataNum++;
               }

               if(buf_st_vOrderIndex.MA_Slope5 > DOUBLE_VALUE_MIN) {
                  DB_MA_Slope5_mData[DB_MA_Slope5_mDataNum] = buf_st_vOrderIndex.MA_Slope5;
                  DB_MA_Slope5_mDataNum++;
               }

               if(buf_st_vOrderIndex.MA_Slope25 > DOUBLE_VALUE_MIN) {
                  DB_MA_Slope25_mData[DB_MA_Slope25_mDataNum] = buf_st_vOrderIndex.MA_Slope25;
                  DB_MA_Slope25_mDataNum++;
               }
 
               if(buf_st_vOrderIndex.MA_Slope75 > DOUBLE_VALUE_MIN) {
                  DB_MA_Slope75_mData[DB_MA_Slope75_mDataNum] = buf_st_vOrderIndex.MA_Slope75;
                  DB_MA_Slope75_mDataNum++;
               }

               if(buf_st_vOrderIndex.BB_Width > DOUBLE_VALUE_MIN) {
                  DB_BB_Width_mData[DB_BB_Width_mDataNum] = buf_st_vOrderIndex.BB_Width;
                  DB_BB_Width_mDataNum++;
               }

               if(buf_st_vOrderIndex.IK_TEN > DOUBLE_VALUE_MIN) {
                  DB_IK_TEN_mData[DB_IK_TEN_mDataNum] = buf_st_vOrderIndex.IK_TEN;
                  DB_IK_TEN_mDataNum++;
               }

               if(buf_st_vOrderIndex.IK_CHI > DOUBLE_VALUE_MIN) {
                  DB_IK_CHI_mData[DB_IK_CHI_mDataNum] = buf_st_vOrderIndex.IK_CHI;
                  DB_IK_CHI_mDataNum++;
               }

               if(buf_st_vOrderIndex.IK_LEG > DOUBLE_VALUE_MIN) {
                  DB_IK_LEG_mData[DB_IK_TEN_mDataNum] = buf_st_vOrderIndex.IK_LEG;
                  DB_IK_LEG_mDataNum++;
               }

               if(buf_st_vOrderIndex.MACD_GC > INT_VALUE_MIN) {
                  DB_MACD_GC_mData[DB_MACD_GC_mDataNum] = buf_st_vOrderIndex.MACD_GC;
                  DB_MACD_GC_mDataNum++;
               }

               if(buf_st_vOrderIndex.MACD_DC > INT_VALUE_MIN) {
                  DB_MACD_DC_mData[DB_MACD_DC_mDataNum] = buf_st_vOrderIndex.MACD_DC;
                  DB_MACD_DC_mDataNum++;
               }

               if(buf_st_vOrderIndex.RSI_VAL > DOUBLE_VALUE_MIN) {
                  DB_RSI_VAL_mData[DB_RSI_VAL_mDataNum] = buf_st_vOrderIndex.RSI_VAL;
                  DB_RSI_VAL_mDataNum++;
               }

               if(buf_st_vOrderIndex.STOC_VAL > DOUBLE_VALUE_MIN) {
                  DB_STOC_VAL_mData[DB_STOC_VAL_mDataNum] = buf_st_vOrderIndex.STOC_VAL;
                  DB_STOC_VAL_mDataNum++;
               }

               if(buf_st_vOrderIndex.STOC_GC > INT_VALUE_MIN) {
                  DB_STOC_GC_mData[DB_STOC_GC_mDataNum] = buf_st_vOrderIndex.STOC_GC;
                  DB_STOC_GC_mDataNum++;
               }

               if(buf_st_vOrderIndex.STOC_DC > INT_VALUE_MIN) {
                  DB_STOC_DC_mData[DB_STOC_DC_mDataNum] = buf_st_vOrderIndex.STOC_DC;
                  DB_STOC_DC_mDataNum++;
               }

               if(buf_st_vOrderIndex.RCI_VAL > DOUBLE_VALUE_MIN) {
                  DB_RCI_VAL_mData[DB_RCI_VAL_mDataNum] = buf_st_vOrderIndex.RCI_VAL;
                  DB_RCI_VAL_mDataNum++;
               }

            }
         }    //  if (MySqlCursorFetchRow(intCursor)) {

      }       // for (i=0; i<Rows; i++) {
//printf( "[%d]テスト　BUY_PROFITに該当する取引の約定時間におけるindex>%d<件に対して、satisfyGeneralRules通過は>%d<件" , __LINE__,
//         countSatisfyMAX,countSatisfy);
   }          // else
   MySqlCursorClose(intCursor);

bool testFlag_over3 = false;  // 実験用。1つでも3件以上のデータがあればtrueになる。
bool testFlag_calcOK = false;  // 実験用。1つでも平均、偏差を計算できていればtrueになる
   
   bool calcFlag = false; 
   if(DB_MA_GC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_GC_mData, DB_MA_GC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesBUY_Profit.MA_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MA_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MA_GC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_MA_DC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_DC_mData, DB_MA_DC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesBUY_Profit.MA_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MA_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MA_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_MA_Slope5_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_Slope5_mData, DB_MA_Slope5_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesBUY_Profit.MA_Slope5_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_Slope5_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MA_Slope5_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MA_Slope5_SIGMA = DOUBLE_VALUE_MIN;
      }
   }
   
   if(DB_MA_Slope25_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_Slope25_mData, DB_MA_Slope25_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesBUY_Profit.MA_Slope25_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_Slope25_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MA_Slope25_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MA_Slope25_SIGMA = DOUBLE_VALUE_MIN;
      }
   }
   
   if(DB_MA_Slope75_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_Slope75_mData, DB_MA_Slope75_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesBUY_Profit.MA_Slope75_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_Slope75_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MA_Slope75_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MA_Slope75_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_BB_Width_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_BB_Width_mData, DB_BB_Width_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesBUY_Profit.BB_Width_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.BB_Width_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.BB_Width_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.BB_Width_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_IK_TEN_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_IK_TEN_mData, DB_IK_TEN_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesBUY_Profit.IK_TEN_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.IK_TEN_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.IK_TEN_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.IK_TEN_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_IK_CHI_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_IK_CHI_mData, DB_IK_CHI_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesBUY_Profit.IK_CHI_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.IK_CHI_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.IK_CHI_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.IK_CHI_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   
   
   if(DB_IK_LEG_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_IK_LEG_mData, DB_IK_LEG_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesBUY_Profit.IK_LEG_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.IK_LEG_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.IK_LEG_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.IK_LEG_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   

   if(DB_MACD_GC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MACD_GC_mData, DB_MA_GC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesBUY_Profit.MACD_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MACD_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MACD_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MACD_GC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_MACD_DC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MACD_DC_mData, DB_MACD_DC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesBUY_Profit.MACD_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MACD_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MACD_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MACD_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   
   
   if(DB_RSI_VAL_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_RSI_VAL_mData, DB_RSI_VAL_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesBUY_Profit.RSI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.RSI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.RSI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.RSI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }
   }      

   if(DB_STOC_VAL_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_STOC_VAL_mData, DB_STOC_VAL_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesBUY_Profit.STOC_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.STOC_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.STOC_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.STOC_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   

   if(DB_STOC_GC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_STOC_GC_mData, DB_MA_GC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesBUY_Profit.STOC_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.STOC_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.STOC_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.STOC_GC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_STOC_DC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_STOC_DC_mData, DB_STOC_DC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesBUY_Profit.STOC_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.STOC_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.STOC_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.STOC_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_RCI_VAL_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_RCI_VAL_mData, DB_RCI_VAL_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesBUY_Profit.RCI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.RCI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.RCI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.RCI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }
   }       
/*
if(testFlag_calcOK == true) {
printf( "[%d]テスト st_vAnalyzedIndexesBUY_Profitのうち、1項目は有効" , __LINE__);
showAnarizedIndex(st_vAnalyzedIndexesBUY_Profit);  // st_vAnalyzedIndexesBUY_Profitの各項目を出力する。
}
else {
printf( "[%d]テスト st_vAnalyzedIndexesBUY_Profitの全項目がNG" , __LINE__);
}
*/
/*if(testFlag_over3 == true) {
printf( "[%d]テスト 1項目は3件以上のデータあり" , __LINE__);
}
else {
printf( "[%d]テスト 全項目3件未満" , __LINE__);
}
if(testFlag_calcOK == true) {
printf( "[%d]テスト 1項目は平均と偏差の計算成功" , __LINE__);
}
else {
printf( "[%d]テスト 全項目、平均と偏差の計算失敗" , __LINE__);
}*/

   // ここまでで、条件を満たす取引を約定したときのindextableテーブルデータを1件読み出せた。
   DB_insert_st_vAnalyzedIndexes(false, st_vAnalyzedIndexesBUY_Profit);  // falseは、バッファが一杯の時のみ書き込み。

        
   return true;
}


void showAnarizedIndex(st_vAnalyzedIndex &bufAnIndex) {
printf( "[%d]テスト st_vAnalyzedIndexの内容" , __LINE__);
printf( "[%d]テスト ステージ番号=>%d<" , __LINE__, bufAnIndex.stageID);
printf( "[%d]テスト 戦略名   =>%s<" , __LINE__, bufAnIndex.strategyID);
printf( "[%d]テスト 通貨ペア  =>%s<" , __LINE__, bufAnIndex.symbol);
printf( "[%d]テスト 時間軸   =>%d<" , __LINE__, bufAnIndex.timeframe);
printf( "[%d]テスト 売買区分  =>%d<" , __LINE__, bufAnIndex.orderType);
printf( "[%d]テスト 損益区分  =>%d<" , __LINE__, bufAnIndex.PLFlag);
printf( "[%d]テスト 基準日   =>%d< = >%s<"  , __LINE__, bufAnIndex.analyzeTime, TimeToStr(bufAnIndex.analyzeTime));
printf( "[%d]テスト DB_MA_GC_MEAN=>%s<"   , __LINE__, DoubleToStr( bufAnIndex.MA_GC_MEAN, global_Digits) );
printf( "[%d]テスト MA_DC_MEAN =>%s<"     , __LINE__, DoubleToStr( bufAnIndex.MA_DC_MEAN, global_Digits) );
printf( "[%d]テスト MA_Slope5_MEAN =>%s<" , __LINE__, DoubleToStr( bufAnIndex.MA_Slope5_MEAN, global_Digits) );
printf( "[%d]テスト MA_Slope25_MEAN =>%s<", __LINE__, DoubleToStr( bufAnIndex.MA_Slope25_MEAN, global_Digits) );
printf( "[%d]テスト MA_Slope75_MEAN =>%s<", __LINE__, DoubleToStr( bufAnIndex.MA_Slope75_MEAN, global_Digits) );
printf( "[%d]テスト BB_Width_MEAN =>%s<"  , __LINE__, DoubleToStr( bufAnIndex.BB_Width_MEAN, global_Digits) );
printf( "[%d]テスト IK_TEN_MEAN =>%s<"    , __LINE__, DoubleToStr( bufAnIndex.IK_TEN_MEAN, global_Digits) );
printf( "[%d]テスト IK_CHI_MEAN =>%s<"    , __LINE__, DoubleToStr( bufAnIndex.IK_CHI_MEAN, global_Digits) );
printf( "[%d]テスト IK_LEG_MEAN =>%s<"    , __LINE__, DoubleToStr( bufAnIndex.IK_LEG_MEAN, global_Digits) );
printf( "[%d]テスト MACD_GC_MEAN =>%s<"   , __LINE__, DoubleToStr( bufAnIndex.MACD_GC_MEAN, global_Digits) );
printf( "[%d]テスト MACD_DC_MEAN =>%s<"   , __LINE__, DoubleToStr( bufAnIndex.MACD_DC_MEAN, global_Digits) );
printf( "[%d]テスト RSI_VAL_MEAN =>%s<"   , __LINE__, DoubleToStr( bufAnIndex.RSI_VAL_MEAN, global_Digits) );
printf( "[%d]テスト STOC_VAL_MEAN =>%s<"  , __LINE__, DoubleToStr( bufAnIndex.STOC_VAL_MEAN, global_Digits) );
printf( "[%d]テスト STOC_GC_MEAN =>%s<"   , __LINE__, DoubleToStr( bufAnIndex.STOC_GC_MEAN, global_Digits) );
printf( "[%d]テスト STOC_DC_MEAN =>%s<"   , __LINE__, DoubleToStr( bufAnIndex.STOC_DC_MEAN, global_Digits) );
printf( "[%d]テスト RCI_VAL_MEAN =>%s<"   , __LINE__, DoubleToStr( bufAnIndex.RCI_VAL_MEAN, global_Digits) );
printf( "[%d]テスト DB_MA_GC_SIGMA=>%s<"   , __LINE__, DoubleToStr( bufAnIndex.MA_GC_SIGMA, global_Digits) );
printf( "[%d]テスト MA_DC_SIGMA =>%s<"     , __LINE__, DoubleToStr( bufAnIndex.MA_DC_SIGMA, global_Digits) );
printf( "[%d]テスト MA_Slope5_SIGMA =>%s<" , __LINE__, DoubleToStr( bufAnIndex.MA_Slope5_SIGMA, global_Digits) );
printf( "[%d]テスト MA_Slope25_SIGMA =>%s<", __LINE__, DoubleToStr( bufAnIndex.MA_Slope25_SIGMA, global_Digits) );
printf( "[%d]テスト MA_Slope75_SIGMA =>%s<", __LINE__, DoubleToStr( bufAnIndex.MA_Slope75_SIGMA, global_Digits) );
printf( "[%d]テスト BB_Width_SIGMA =>%s<"  , __LINE__, DoubleToStr( bufAnIndex.BB_Width_SIGMA, global_Digits) );
printf( "[%d]テスト IK_TEN_SIGMA =>%s<"    , __LINE__, DoubleToStr( bufAnIndex.IK_TEN_SIGMA, global_Digits) );
printf( "[%d]テスト IK_CHI_SIGMA =>%s<"    , __LINE__, DoubleToStr( bufAnIndex.IK_CHI_SIGMA, global_Digits) );
printf( "[%d]テスト IK_LEG_SIGMA =>%s<"    , __LINE__, DoubleToStr( bufAnIndex.IK_LEG_SIGMA, global_Digits) );
printf( "[%d]テスト MACD_GC_SIGMA =>%s<"   , __LINE__, DoubleToStr( bufAnIndex.MACD_GC_SIGMA, global_Digits) );
printf( "[%d]テスト MACD_DC_SIGMA =>%s<"   , __LINE__, DoubleToStr( bufAnIndex.MACD_DC_SIGMA, global_Digits) );
printf( "[%d]テスト RSI_VAL_SIGMA =>%s<"   , __LINE__, DoubleToStr( bufAnIndex.RSI_VAL_SIGMA, global_Digits) );
printf( "[%d]テスト STOC_VAL_SIGMA =>%s<"  , __LINE__, DoubleToStr( bufAnIndex.STOC_VAL_SIGMA, global_Digits) );
printf( "[%d]テスト STOC_GC_SIGMA =>%s<"   , __LINE__, DoubleToStr( bufAnIndex.STOC_GC_SIGMA, global_Digits) );
printf( "[%d]テスト STOC_DC_SIGMA =>%s<"   , __LINE__, DoubleToStr( bufAnIndex.STOC_DC_SIGMA, global_Digits) );
printf( "[%d]テスト RCI_VAL_SIGMA =>%s<"   , __LINE__, DoubleToStr( bufAnIndex.RCI_VAL_SIGMA, global_Digits) );
}
//
// 平均、偏差を計算するための配列及び変数を初期化する。
//
void init_Mean_Sig_Variables() {
   // 1 移動平均:MA
   ArrayInitialize(DB_MA_GC_mData,      DOUBLE_VALUE_MIN);
   ArrayInitialize(DB_MA_DC_mData,      DOUBLE_VALUE_MIN);
   ArrayInitialize(DB_MA_Slope5_mData,  DOUBLE_VALUE_MIN);
   ArrayInitialize(DB_MA_Slope25_mData, DOUBLE_VALUE_MIN);
   ArrayInitialize(DB_MA_Slope75_mData, DOUBLE_VALUE_MIN);
   // 2 ボリンジャーバンドBB
   ArrayInitialize(DB_BB_Width_mData,   DOUBLE_VALUE_MIN);
   // 3 一目均衡表:IK
   ArrayInitialize(DB_IK_TEN_mData,     DOUBLE_VALUE_MIN);
   ArrayInitialize(DB_IK_CHI_mData,     DOUBLE_VALUE_MIN);
   ArrayInitialize(DB_IK_LEG_mData,     DOUBLE_VALUE_MIN);
   // 4 MACD:MACD
   ArrayInitialize(DB_MACD_GC_mData,    DOUBLE_VALUE_MIN);
   ArrayInitialize(DB_MACD_DC_mData,    DOUBLE_VALUE_MIN);
   //   
   // オシレーター分析
   // 1 RSI:RSI
   ArrayInitialize(DB_RSI_VAL_mData,    DOUBLE_VALUE_MIN);
   // 2 ストキャスティクス:STOC
   ArrayInitialize(DB_STOC_VAL_mData,   DOUBLE_VALUE_MIN);
   ArrayInitialize(DB_STOC_GC_mData,    DOUBLE_VALUE_MIN);
   ArrayInitialize(DB_STOC_DC_mData,    DOUBLE_VALUE_MIN);
   // 4 RCI:RCI
   ArrayInitialize(DB_RCI_VAL_mData,    DOUBLE_VALUE_MIN);

   // トレンド分析
   // 1 移動平均:MA
   DB_MA_GC_mDataNum = 0;
   DB_MA_DC_mDataNum = 0;
   DB_MA_Slope5_mDataNum = 0;
   DB_MA_Slope25_mDataNum = 0;
   DB_MA_Slope75_mDataNum = 0;
   // 2 ボリンジャーバンドBB
   DB_BB_Width_mDataNum = 0;
   // 3 一目均衡表:IK
   DB_IK_TEN_mDataNum = 0;
   DB_IK_CHI_mDataNum = 0;
   DB_IK_LEG_mDataNum = 0;
   // 4 MACD:MACD
   DB_MACD_GC_mDataNum = 0;
   DB_MACD_DC_mDataNum = 0;
   //
   // オシレーター分析
   // 1 RSI:RSI
   DB_RSI_VAL_mDataNum = 0;
   // 2 ストキャスティクス:STOC
   DB_STOC_VAL_mDataNum = 0;
   DB_STOC_GC_mDataNum = 0;
   DB_STOC_DC_mDataNum = 0;
   // 4 RCI:RCI
   DB_RCI_VAL_mDataNum = 0;
}


// 引数で特定できる仮想取引をvtradetableテーブルから削除する。
bool DB_delete_vAnalyzedIndex(
                   int    mStageID,       // ステージ番号。正の時は、このステージ番号以上を削除。負の時は、ステージ番号を削除条件に加えない。
                   string mStrategyID, // 戦略名。　　　長さ0の時は、戦略名を削除条件に加えない。
                   string mSymbol,  // 仮想取引の通貨ペア。長さ0の時は、戦略名を削除条件に加えない。
                   int    mTimeframe_calc,  // PERIOD_M15。指標計算時の時間軸。15分足のデータを使って指標を計算していれば、PERIOD_M15。負の時は、削除条件に加えない。
                   int    mOrderType,     // 売買区分。　　OP_BUY及びOP_SELL以外の時は、削除条件に加えない。
                   int    mPLFlag,           // 損益区分。vPROFIT, vLOSS以外の時は、削除条件に加えない。
                   datetime    mAnalyzeTime   // 平均、偏差計算時の基準時間。負の時は、削除条件に加えない。
                 ) {
   string bufCondition = "";

   // ステージ番号
   if(mStageID < 0) {  // 負の時は、ステージ番号を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " stageID >= " + IntegerToString(mStageID);
   }
    
   // 戦略名
   if(StringLen(mStrategyID) <= 0) { // 長さ0の時は、戦略名を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " strategyID = \'" + mStrategyID + "\' ";
   }
  
   // 通貨ペア名
   if(StringLen(mSymbol) <= 0) { // 長さ0の時は、通貨ペア名を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " symbol = \'" + mSymbol + "\' ";
   }

   // 時間軸(指標計算時のタイムフレーム)
   if(mTimeframe_calc < 0) {  // 負の時は、チケット番号を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " timeframe = " + IntegerToString(mTimeframe_calc);
   }

   // 売買区分
   if(mOrderType != OP_BUY && mOrderType != OP_SELL) {  // OP_BUY, OP_SELL以外の時は、削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " orderType = " + IntegerToString(mOrderType);
   }   

   // 損益区分
   if(mPLFlag != vPROFIT && mPLFlag != vLOSS) {  // vPROFIT, vLOSS以外の時は、削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " PLFlag = " + IntegerToString(mPLFlag);
   }   

   // 平均、偏差計算時の基準時間
   if(mAnalyzeTime < 0) {  // 負の時は、チケット番号を削除条件に加えない。
   }
   else {
      if(StringLen(bufCondition) > 0) {  // 既にbufConditionに条件が入っている場合は、"and"を追加する。
         bufCondition = bufCondition + " and ";
      }
      bufCondition = bufCondition + " analyzeTime = " + IntegerToString(mAnalyzeTime);
   }

   string Query = "delete from vAnalyzedIndex";
   if(StringLen(bufCondition) > 0) {
      Query = Query + " where " + bufCondition;
   }

//printf( "[%d]テスト　delete_vAnalyzedIndexの削除用SQL:%s" , __LINE__, Query);     

   if (MySqlExecute(DB,Query) == true) {
      return true;
   }
   else {
      printf( "[%d]エラー  delete_vAnalyzedIndex削除失敗=%s" , __LINE__ ,MySqlErrorDescription);
      return false;
   }
}


//+-----------------------------------------------------------------------------+
//| create_Stoc_vOrdersBUY_LOSSのDB対応版。
//+-----------------------------------------------------------------------------+
// 仮想取引を評価し、戦略別・通貨ペア別・タイムフレーム別・売買区分別・損益別の各指標の平均と偏差を計算する。
// 約定日が、引数mFROM_vOrder_openTimeから、mCalcTimeまでの約定とそれに紐づく指標データを平均、偏差の計算処理対象とする。
// 仮想取引が買い＋損失である時の指標の平均と偏差を計算する。
// 計算結果は、グローバル変数st_vAnalyzedIndexesBUY_Lossに入る。
bool DB_create_Stoc_vOrdersBUY_LOSS(int      mStageID,              // 入力：計算中のステージ番号
                                    string   mStrategyID,           // 入力：計算中の戦略名
                                    string   mSymbol,               // 入力：計算中の通貨ペア
                                    int      mTimeframe_calc,       // 入力：PERIOD_M15。指標を計算する時に使う時間軸
                                    datetime mCalcTime,             // 入力：計算基準時間。評価対象となる仮想取引の約定時間がこの時間まで。
                                    datetime mFROM_vOrder_openTime  // 入力：評価対象となる仮想取引の約定時間がこの値以降。
                                     ) {
   // 対象とする最初の時間が負の場合は、仮想取引の先頭から計算対象とする。
   if(mFROM_vOrder_openTime < 0) {
      mFROM_vOrder_openTime = 0;
   }

   if(mFROM_vOrder_openTime > mCalcTime) {
      printf( "[%d]テスト 計算対象取引の先頭時間%d:%sが末尾時間%d:%sより大きい" , __LINE__,
                mFROM_vOrder_openTime, TimeToStr(mFROM_vOrder_openTime),
                 mCalcTime, TimeToStr(mCalcTime));
      return false;
   }

   // キー項目の初期値を設定する
   st_vAnalyzedIndexesBUY_Loss.stageID     = mStageID;
   st_vAnalyzedIndexesBUY_Loss.strategyID  = mStrategyID;
   st_vAnalyzedIndexesBUY_Loss.symbol      = mSymbol;
   st_vAnalyzedIndexesBUY_Loss.timeframe   = mTimeframe_calc;
   st_vAnalyzedIndexesBUY_Loss.orderType   = OP_BUY;
   st_vAnalyzedIndexesBUY_Loss.PLFlag      = vLOSS; // vPL_DEFAULT=0, vPROFIT=1, vLOSS=-1
   st_vAnalyzedIndexesBUY_Loss.analyzeTime = mCalcTime;
    
   // 4種のどのパターンで処理をするか。
   int BS_PL_FLAG = vBUY_LOSS;

   if(StringLen(mStrategyID) <= 0) {
printf( "[%d]テスト 戦略名未設定" , __LINE__);
      return false;
   }
   if(StringLen(mSymbol) <= 0) {
printf( "[%d]テスト 通貨ペア未設定" , __LINE__);
      return false;
   }
   if(mTimeframe_calc < 0) {
printf( "[%d]テスト 時間軸未設定" , __LINE__);   
      return false;
   }


   int    Index_of_st_vOrderIndexes = -1;
   double indexMean  = 0.0;
   double indexSigma = 0.0;

   bool retFlag = false;  
   int    DB_MEAN_SIGMA_Num = 0;
   double DB_MEAN_SIGMA_Data[DB_VTRADENUM_MAX];
      
  //
  // １．買いかつ損失の仮想取引のオープン時各指標値は、ここから。
  //
  // 変数の初期化。平均と偏差を計算するための配列MA_GC_mData[i]などを初期化。
   DB_MEAN_SIGMA_Num = 0;
   ArrayInitialize(DB_MEAN_SIGMA_Data, 0.0);


   //    
   // ①買いかつ損失の仮想取引を検索する　→　副問い合わせtmpTableファイルに格納する。　　←　基準時間に近い約定ほど重みづけしたり、最近の数％件数のみを対象とするなど、工夫する。
   string Query = "";

   Query = Query + " SELECT symbol, openTime FROM vtradetable ";
   Query = Query + " where ";
   Query = Query + " stageID = " + IntegerToString(mStageID);
   Query = Query + " AND ";
   Query = Query + " strategyID = \'" + mStrategyID + "\'" ;
   Query = Query + " AND " ;
   Query = Query + " symbol = \'" + mSymbol + "\'" ;
   Query = Query + " AND "; 
   Query = Query + " orderType = " + IntegerToString(OP_BUY) ;
   Query = Query + " AND ( " ;
   // 約定日が、引数mFROM_vOrder_openTimeから、mCalcTimeまでの約定とそれに紐づく指標データを平均、偏差の計算処理対象とする。
   Query = Query + " ( (openTime >= " + IntegerToString(mFROM_vOrder_openTime) + " AND openTime <= " + IntegerToString(mCalcTime) + ") " ;
   Query = Query + "AND " ;

   // 決済損益の計算対象取引は、決済日closeTimeがmFROM_vOrder_openTimeとmCalcTimeの間にあること。決済損益closePL < 0.0であること。
   Query = Query + "(closeTime >= " + IntegerToString(mFROM_vOrder_openTime) + " AND closeTime <= " + IntegerToString(mCalcTime) + ") AND closePL < 0.0)";
   Query = Query + " OR ";
   
   // 評価損益の計算対象取引は、決済日が0のままか、決済されていたとしても決済日closeTimeがmTO_vOrder_openTimeよりあとであること。評価日estimateTimeがmCalcTimeと同じかそれより前。決済損益closePL < 0.0であること。
   Query = Query + "( (estimateTime > 0 AND estimateTime <= " + IntegerToString(mCalcTime) + ") AND (closeTime = 0 OR closeTime > " + IntegerToString(mCalcTime) + ") AND estimatePL < 0.0))";
   

   // ②副問い合わせの戻り値Symbol, openTime(, timeframeは引数timeframeを使う）をキー項目として、平均と偏差の計算対象とする指標データを検索する。
   //  なお、indextable.calc_dtを使って降順に並び変えておく。計算対象がDB_VTRADENUM_MAX件以上になったとしても、影響力が大きいとみなせる最近の指標データを計算対象にできるため。
   // →上記①で求めた副問い合わせの前後に、indextableの検索をする部品を追加する。
   string preQuery = "";   
   preQuery = preQuery + " SELECT * FROM indextable ";
   preQuery = preQuery + " WHERE ";
   preQuery = preQuery + " timeframe = "+ IntegerToString(mTimeframe_calc);
   preQuery = preQuery + " AND ";
   preQuery = preQuery + " (symbol, calc_dt) = ";
   preQuery = preQuery + " ANY(SELECT * FROM ( ";
   //
   // indextable検索用部品preQueryに、副問い合わせQueryに結合する
   Query = preQuery + Query;   
   //
   // 副問い合わせの末尾を結合
   Query = Query + " ) AS temp1) ORDER BY calc_dt DESC;";

   int i;
   string buf_symbol = "";
   int    buf_timeframe = 0;
   int    buf_calc_dt = 0;
   string buf_calc_dt_str = "";
   
   int    buf_read_integer = 0;
   double buf_read_double  = 0.0;
   int    countSatisfy    = 0; // satisfyGeneralRules関数で条件を満たしたindexテーブルの個数
   int    countSatisfyMAX = 0; // satisfyGeneralRules関数の判定対象としてindexテーブルの総数

   init_Mean_Sig_Variables();  // 平均、偏差を計算するためのデータを格納する配列及びデータ個数を示す変数を初期化する。
   int intCursor = MySqlCursorOpen(DB, Query);

   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);              
   }
   else {
      int Rows = MySqlCursorRows(intCursor);
//printf( "[%d]テスト　計算基準時間%sのBUY_LOSSに該当する取引の約定時間におけるindex件数:%d件%s" , __LINE__, TimeToStr(mCalcTime), Rows, Query);              

      st_vOrderIndex buf_st_vOrderIndex;   // indextableテーブルから1行読み込んだデータを一時的に保存する。
      countSatisfyMAX = Rows;    // BUY_LOSSに該当する取引の約定時間におけるindex件数。かつ、satisfyGeneralRules関数による絞り込み前のindex件数。
      countSatisfy    = 0;       // satisfyGeneralRules関数による絞り込み通過件数を0で初期化。
      for (i = 0; i < Rows; i++) {
         // DBから読み込んだ1件の指標データを一時的に変数に格納する。
         
         init_st_vOrderIndex(buf_st_vOrderIndex);// 一時的に値を格納する変数の初期化。

         if (MySqlCursorFetchRow(intCursor)) {
            // カーソルの指す1件を取得する。
            // 
            buf_st_vOrderIndex.symbol      = MySqlGetFieldAsString(intCursor, 0);
            buf_st_vOrderIndex.timeframe   = MySqlGetFieldAsInt(intCursor,    1);
            buf_st_vOrderIndex.calcTime    = MySqlGetFieldAsInt(intCursor,    2);
            buf_calc_dt_str = MySqlGetFieldAsString(intCursor, 3);
            
            buf_read_integer = MySqlGetFieldAsInt(intCursor, 4);
            buf_st_vOrderIndex.MA_GC = buf_read_integer;

            buf_read_integer = MySqlGetFieldAsInt(intCursor, 5);
            buf_st_vOrderIndex.MA_DC = buf_read_integer;

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 6);
            buf_st_vOrderIndex.MA_Slope5 = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 7);
            buf_st_vOrderIndex.MA_Slope25 = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 8);
            buf_st_vOrderIndex.MA_Slope75 = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 9);
            buf_st_vOrderIndex.BB_Width = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,10);
            buf_st_vOrderIndex.IK_TEN = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,11);
            buf_st_vOrderIndex.IK_CHI = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,12);
            buf_st_vOrderIndex.IK_LEG = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_integer = MySqlGetFieldAsInt(intCursor,13);
            buf_st_vOrderIndex.MACD_GC = buf_read_integer;

            buf_read_integer = MySqlGetFieldAsInt(intCursor,14);
            buf_st_vOrderIndex.MACD_DC = buf_read_integer;

            buf_read_double =  MySqlGetFieldAsInt(intCursor,15);
            buf_st_vOrderIndex.RSI_VAL= NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,16);
            buf_st_vOrderIndex.STOC_VAL= NormalizeDouble(buf_read_double, global_Digits);

            buf_read_integer = MySqlGetFieldAsInt(intCursor,17);
            buf_st_vOrderIndex.STOC_GC = buf_read_integer;

            buf_read_integer = MySqlGetFieldAsInt(intCursor,18);
            buf_st_vOrderIndex.STOC_DC = buf_read_integer;

            buf_read_double =  MySqlGetFieldAsInt(intCursor,19);
            buf_st_vOrderIndex.RCI_VAL= NormalizeDouble(buf_read_double, global_Digits);


            // satisfyGeneralRules関数を使って、読みだしたindextableテーブルデータがルールを満たしているかを確認し、
            // 条件を満たしていなければ、廃棄する。
            bool flag_satisfyGeneralRules = satisfyGeneralRules(buf_st_vOrderIndex, BS_PL_FLAG);
            if(flag_satisfyGeneralRules == false) {
               // 条件を満たさなかった時は、何もしない               
            }
            else {
               countSatisfy++; // satisfyGeneralRules関数を使った絞り込みを通過した件数を1増やす。

               // ルールを満たした指標（BUY/PROFIT等の条件を満たした取引を約定したときの指標）のため、
               // 各項目の値を平均、偏差計算用配列にコピーする。
               if(buf_st_vOrderIndex.MA_GC > INT_VALUE_MIN) {
                  DB_MA_GC_mData[DB_MA_GC_mDataNum] = buf_st_vOrderIndex.MA_GC;
                  DB_MA_GC_mDataNum++;
               }

               if(buf_st_vOrderIndex.MA_DC > INT_VALUE_MIN) {
                  DB_MA_DC_mData[DB_MA_DC_mDataNum] = buf_st_vOrderIndex.MA_DC;
                  DB_MA_DC_mDataNum++;
               }

               if(buf_st_vOrderIndex.MA_Slope5 > DOUBLE_VALUE_MIN) {
                  DB_MA_Slope5_mData[DB_MA_Slope5_mDataNum] = buf_st_vOrderIndex.MA_Slope5;
                  DB_MA_Slope5_mDataNum++;
               }

               if(buf_st_vOrderIndex.MA_Slope25 > DOUBLE_VALUE_MIN) {
                  DB_MA_Slope25_mData[DB_MA_Slope25_mDataNum] = buf_st_vOrderIndex.MA_Slope25;
                  DB_MA_Slope25_mDataNum++;
               }
 
               if(buf_st_vOrderIndex.MA_Slope75 > DOUBLE_VALUE_MIN) {
                  DB_MA_Slope75_mData[DB_MA_Slope75_mDataNum] = buf_st_vOrderIndex.MA_Slope75;
                  DB_MA_Slope75_mDataNum++;
               }

               if(buf_st_vOrderIndex.BB_Width > DOUBLE_VALUE_MIN) {
                  DB_BB_Width_mData[DB_BB_Width_mDataNum] = buf_st_vOrderIndex.BB_Width;
                  DB_BB_Width_mDataNum++;
               }

               if(buf_st_vOrderIndex.IK_TEN > DOUBLE_VALUE_MIN) {
                  DB_IK_TEN_mData[DB_IK_TEN_mDataNum] = buf_st_vOrderIndex.IK_TEN;
                  DB_IK_TEN_mDataNum++;
               }

               if(buf_st_vOrderIndex.IK_CHI > DOUBLE_VALUE_MIN) {
                  DB_IK_CHI_mData[DB_IK_CHI_mDataNum] = buf_st_vOrderIndex.IK_CHI;
                  DB_IK_CHI_mDataNum++;
               }

               if(buf_st_vOrderIndex.IK_LEG > DOUBLE_VALUE_MIN) {
                  DB_IK_LEG_mData[DB_IK_TEN_mDataNum] = buf_st_vOrderIndex.IK_LEG;
                  DB_IK_LEG_mDataNum++;
               }

               if(buf_st_vOrderIndex.MACD_GC > INT_VALUE_MIN) {
                  DB_MACD_GC_mData[DB_MACD_GC_mDataNum] = buf_st_vOrderIndex.MACD_GC;
                  DB_MACD_GC_mDataNum++;
               }

               if(buf_st_vOrderIndex.MACD_DC > INT_VALUE_MIN) {
                  DB_MACD_DC_mData[DB_MACD_DC_mDataNum] = buf_st_vOrderIndex.MACD_DC;
                  DB_MACD_DC_mDataNum++;
               }

               if(buf_st_vOrderIndex.RSI_VAL > DOUBLE_VALUE_MIN) {
                  DB_RSI_VAL_mData[DB_RSI_VAL_mDataNum] = buf_st_vOrderIndex.RSI_VAL;
                  DB_RSI_VAL_mDataNum++;
               }

               if(buf_st_vOrderIndex.STOC_VAL > DOUBLE_VALUE_MIN) {
                  DB_STOC_VAL_mData[DB_STOC_VAL_mDataNum] = buf_st_vOrderIndex.STOC_VAL;
                  DB_STOC_VAL_mDataNum++;
               }

               if(buf_st_vOrderIndex.STOC_GC > INT_VALUE_MIN) {
                  DB_STOC_GC_mData[DB_STOC_GC_mDataNum] = buf_st_vOrderIndex.STOC_GC;
                  DB_STOC_GC_mDataNum++;
               }

               if(buf_st_vOrderIndex.STOC_DC > INT_VALUE_MIN) {
                  DB_STOC_DC_mData[DB_STOC_DC_mDataNum] = buf_st_vOrderIndex.STOC_DC;
                  DB_STOC_DC_mDataNum++;
               }

               if(buf_st_vOrderIndex.RCI_VAL > DOUBLE_VALUE_MIN) {
                  DB_RCI_VAL_mData[DB_RCI_VAL_mDataNum] = buf_st_vOrderIndex.RCI_VAL;
                  DB_RCI_VAL_mDataNum++;
               }

            }
         }    //  if (MySqlCursorFetchRow(intCursor)) {

      }       // for (i=0; i<Rows; i++) {
//printf( "[%d]テスト　BUY_LOSSに該当する取引の約定時間におけるindex>%d<件に対して、satisfyGeneralRules通過は>%d<件" , __LINE__,
//         countSatisfyMAX,countSatisfy);
   }          // else
   MySqlCursorClose(intCursor);

bool testFlag_over3 = false;  // 実験用。1つでも3件以上のデータがあればtrueになる。
bool testFlag_calcOK = false;  // 実験用。1つでも平均、偏差を計算できていればtrueになる
   
   bool calcFlag = false; 
   if(DB_MA_GC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_GC_mData, DB_MA_GC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesBUY_Loss.MA_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.MA_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MA_GC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_MA_DC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_DC_mData, DB_MA_DC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesBUY_Loss.MA_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.MA_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MA_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_MA_Slope5_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_Slope5_mData, DB_MA_Slope5_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesBUY_Loss.MA_Slope5_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_Slope5_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.MA_Slope5_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MA_Slope5_SIGMA = DOUBLE_VALUE_MIN;
      }
   }
   
   if(DB_MA_Slope25_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_Slope25_mData, DB_MA_Slope25_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesBUY_Loss.MA_Slope25_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_Slope25_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.MA_Slope25_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MA_Slope25_SIGMA = DOUBLE_VALUE_MIN;
      }
   }
   
   if(DB_MA_Slope75_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_Slope75_mData, DB_MA_Slope75_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesBUY_Loss.MA_Slope75_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_Slope75_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.MA_Slope75_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MA_Slope75_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_BB_Width_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_BB_Width_mData, DB_BB_Width_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesBUY_Loss.BB_Width_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.BB_Width_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.BB_Width_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.BB_Width_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_IK_TEN_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_IK_TEN_mData, DB_IK_TEN_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesBUY_Loss.IK_TEN_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.IK_TEN_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.IK_TEN_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.IK_TEN_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_IK_CHI_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_IK_CHI_mData, DB_IK_CHI_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesBUY_Loss.IK_CHI_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.IK_CHI_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.IK_CHI_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.IK_CHI_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   
   
   if(DB_IK_LEG_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_IK_LEG_mData, DB_IK_LEG_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesBUY_Loss.IK_LEG_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.IK_LEG_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.IK_LEG_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.IK_LEG_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   

   if(DB_MACD_GC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MACD_GC_mData, DB_MA_GC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesBUY_Loss.MACD_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MACD_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.MACD_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MACD_GC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_MACD_DC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MACD_DC_mData, DB_MACD_DC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesBUY_Loss.MACD_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MACD_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.MACD_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MACD_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   
   
   if(DB_RSI_VAL_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_RSI_VAL_mData, DB_RSI_VAL_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesBUY_Loss.RSI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.RSI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.RSI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.RSI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }
   }      

   if(DB_STOC_VAL_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_STOC_VAL_mData, DB_STOC_VAL_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesBUY_Loss.STOC_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.STOC_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.STOC_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.STOC_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   

   if(DB_STOC_GC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_STOC_GC_mData, DB_MA_GC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesBUY_Loss.STOC_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.STOC_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.STOC_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.STOC_GC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_STOC_DC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_STOC_DC_mData, DB_STOC_DC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesBUY_Loss.STOC_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.STOC_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.STOC_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.STOC_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_RCI_VAL_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_RCI_VAL_mData, DB_RCI_VAL_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesBUY_Loss.RCI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.RCI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesBUY_Loss.RCI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.RCI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }
   }       

// showAnarizedIndex(st_vAnalyzedIndexesBUY_Loss);  // st_vAnalyzedIndexesBUY_Lossの各項目を出力する。

/*if(testFlag_over3 == true) {
printf( "[%d]テスト 1項目は3件以上のデータあり" , __LINE__);
}
else {
printf( "[%d]テスト 全項目3件未満" , __LINE__);
}
if(testFlag_calcOK == true) {
printf( "[%d]テスト 1項目は平均と偏差の計算成功" , __LINE__);
}
else {
printf( "[%d]テスト 全項目、平均と偏差の計算失敗" , __LINE__);
}*/

   // ここまでで、条件を満たす取引を約定したときのindextableテーブルデータを1件読み出せた。
   DB_insert_st_vAnalyzedIndexes(false, st_vAnalyzedIndexesBUY_Loss);  // falseは、バッファが一杯の時のみ書き込み。

        
   return true;
}



//+-----------------------------------------------------------------------------+
//| create_Stoc_vOrdersSELL_PROFITのDB対応版。
//+-----------------------------------------------------------------------------+
// 仮想取引を評価し、戦略別・通貨ペア別・タイムフレーム別・売買区分別・損益別の各指標の平均と偏差を計算する。
// 約定日が、引数mFROM_vOrder_openTimeから、mCalcTimeまでの約定とそれに紐づく指標データを平均、偏差の計算処理対象とする。
// 仮想取引が売り＋利益である時の指標の平均と偏差を計算する。
// 計算結果は、グローバル変数st_vAnalyzedIndexesSELL_Profitに入る。
bool DB_create_Stoc_vOrdersSELL_PROFIT(int      mStageID,             // 入力：計算中のステージ番号
                                      string   mStrategyID,           // 入力：計算中の戦略名
                                      string   mSymbol,               // 入力：計算中の通貨ペア
                                      int      mTimeframe_calc,       // 入力：PERIOD_M15。指標を計算する時に使う時間軸
                                      datetime mCalcTime,             // 入力：計算基準時間。評価対象となる仮想取引の約定時間がこの時間まで。
                                      datetime mFROM_vOrder_openTime  // 入力：評価対象となる仮想取引の約定時間がこの値以降。
                                     ) {
   // 対象とする最初の時間が負の場合は、仮想取引の先頭から計算対象とする。
   if(mFROM_vOrder_openTime < 0) {
      mFROM_vOrder_openTime = 0;
   }

   if(mFROM_vOrder_openTime > mCalcTime) {
      printf( "[%d]テスト 計算対象取引の先頭時間%d:%sが末尾時間%d:%sより大きい" , __LINE__,
                mFROM_vOrder_openTime, TimeToStr(mFROM_vOrder_openTime),
                 mCalcTime, TimeToStr(mCalcTime));
      return false;
   }

   // キー項目の初期値を設定する
   st_vAnalyzedIndexesSELL_Profit.stageID     = mStageID;
   st_vAnalyzedIndexesSELL_Profit.strategyID  = mStrategyID;
   st_vAnalyzedIndexesSELL_Profit.symbol      = mSymbol;
   st_vAnalyzedIndexesSELL_Profit.timeframe   = mTimeframe_calc;
   st_vAnalyzedIndexesSELL_Profit.orderType   = OP_SELL;
   st_vAnalyzedIndexesSELL_Profit.PLFlag      = vPROFIT; // vPL_DEFAULT=0, vPROFIT=1, vLOSS=-1
   st_vAnalyzedIndexesSELL_Profit.analyzeTime = mCalcTime;
    
   // 4種のどのパターンで処理をするか。
   int BS_PL_FLAG = vSELL_PROFIT;

   if(StringLen(mStrategyID) <= 0) {
printf( "[%d]テスト 戦略名未設定" , __LINE__);
      return false;
   }
   if(StringLen(mSymbol) <= 0) {
printf( "[%d]テスト 通貨ペア未設定" , __LINE__);
      return false;
   }
   if(mTimeframe_calc < 0) {
printf( "[%d]テスト 時間軸未設定" , __LINE__);   
      return false;
   }


   int    Index_of_st_vOrderIndexes = -1;
   double indexMean  = 0.0;
   double indexSigma = 0.0;

   bool retFlag = false;  
   int    DB_MEAN_SIGMA_Num = 0;
   double DB_MEAN_SIGMA_Data[DB_VTRADENUM_MAX];
      
  //
  // １．売りかつ利益の仮想取引のオープン時各指標値は、ここから。
  //
  // 変数の初期化。平均と偏差を計算するための配列MA_GC_mData[i]などを初期化。
   DB_MEAN_SIGMA_Num = 0;
   ArrayInitialize(DB_MEAN_SIGMA_Data, 0.0);


   //    
   // ①売りかつ利益の仮想取引を検索する　→　副問い合わせtmpTableファイルに格納する。　　←　基準時間に近い約定ほど重みづけしたり、最近の数％件数のみを対象とするなど、工夫する。
   string Query = "";
   Query = Query + " SELECT symbol, openTime FROM vtradetable ";
   Query = Query + " where ";
   Query = Query + " stageID = " + IntegerToString(mStageID);
   Query = Query + " AND ";
   Query = Query + " strategyID = \'" + mStrategyID + "\'" ;
   Query = Query + " AND " ;
   Query = Query + " symbol = \'" + mSymbol + "\'" ;
   Query = Query + " AND "; 
   Query = Query + " orderType = " + IntegerToString(OP_SELL) ;
   Query = Query + " AND ( " ;   
   // 約定日が、引数mFROM_vOrder_openTimeから、mCalcTimeまでの約定とそれに紐づく指標データを平均、偏差の計算処理対象とする。
   Query = Query + " ( (openTime >= " + IntegerToString(mFROM_vOrder_openTime) + " AND openTime <= " + IntegerToString(mCalcTime) + ") " ;
   Query = Query + "AND " ;
   
   // 決済損益の計算対象取引は、決済日closeTimeがmFROM_vOrder_openTimeとmCalcTimeの間にあること。決済損益closePL > 0.0であること。
   Query = Query + "(closeTime >= " + IntegerToString(mFROM_vOrder_openTime) + " AND closeTime <= " + IntegerToString(mCalcTime) + ") AND closePL > 0.0)";
   Query = Query + " OR ";
      
   // 評価損益の計算対象取引は、決済日が0のままか、決済されていたとしても決済日closeTimeがmTO_vOrder_openTimeよりあとであること。評価日estimateTimeがmCalcTimeと同じかそれより前。評価損益estimatePL > 0.0であること。
   Query = Query + "( (estimateTime > 0 AND estimateTime <= " + IntegerToString(mCalcTime) + ") AND (closeTime = 0 OR closeTime > " + IntegerToString(mCalcTime) + ") AND estimatePL > 0.0))";

   // ②副問い合わせの戻り値Symbol, openTime(, timeframeは引数timeframeを使う）をキー項目として、平均と偏差の計算対象とする指標データを検索する。
   //  なお、indextable.calc_dtを使って降順に並び変えておく。計算対象がDB_VTRADENUM_MAX件以上になったとしても、影響力が大きいとみなせる最近の指標データを計算対象にできるため。
   // →上記①で求めた副問い合わせの前後に、indextableの検索をする部品を追加する。
   string preQuery = "";   
   preQuery = preQuery + " SELECT * FROM indextable ";
   preQuery = preQuery + " WHERE ";
   preQuery = preQuery + " timeframe = "+ IntegerToString(mTimeframe_calc);
   preQuery = preQuery + " AND ";
   preQuery = preQuery + " (symbol, calc_dt) = ";
   preQuery = preQuery + " ANY(SELECT * FROM ( ";
      
   //
   // indextable検索用部品preQueryに、副問い合わせQueryに結合する
   Query = preQuery + Query;   
   //
   // 副問い合わせの末尾を結合
   Query = Query + " ) AS temp1) ORDER BY calc_dt DESC;";

   
   sqlGetIndexSellProfit = "";
   sqlGetIndexSellProfit = sqlGetIndexSellProfit + " SELECT " + IntegerToString(mStageID) + ", " + IntegerToString(OP_SELL) + ", " + IntegerToString(vPROFIT) + ", * FROM indextable ";
   sqlGetIndexSellProfit = sqlGetIndexSellProfit + " WHERE ";
   sqlGetIndexSellProfit = sqlGetIndexSellProfit + " timeframe = "+ IntegerToString(mTimeframe_calc);
   sqlGetIndexSellProfit = sqlGetIndexSellProfit + " AND ";
   sqlGetIndexSellProfit = sqlGetIndexSellProfit + " (symbol, calc_dt) = ";
   sqlGetIndexSellProfit = sqlGetIndexSellProfit + " ANY(SELECT * FROM ( ";
   sqlGetIndexSellProfit = sqlGetIndexSellProfit + Query + " ) AS temp1) ORDER BY calc_dt DESC;";


   int i;
   string buf_symbol = "";
   int    buf_timeframe = 0;
   int    buf_calc_dt = 0;
   string buf_calc_dt_str = "";
   
   int    buf_read_integer = 0;
   double buf_read_double  = 0.0;
   int    countSatisfy    = 0; // satisfyGeneralRules関数で条件を満たしたindexテーブルの個数
   int    countSatisfyMAX = 0; // satisfyGeneralRules関数の判定対象としてindexテーブルの総数

   init_Mean_Sig_Variables();  // 平均、偏差を計算するためのデータを格納する配列及びデータ個数を示す変数を初期化する。
   int intCursor = MySqlCursorOpen(DB, Query);

   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);              
   }
   else {
      int Rows = MySqlCursorRows(intCursor);
//printf( "[%d]テスト　計算基準時間%sのSELL_PROFITに該当する取引の約定時間におけるindex件数:%d件%s" , __LINE__, TimeToStr(mCalcTime), Rows, Query);              

      st_vOrderIndex buf_st_vOrderIndex;   // indextableテーブルから1行読み込んだデータを一時的に保存する。
      countSatisfyMAX = Rows;    // SELL_PROFITに該当する取引の約定時間におけるindex件数。かつ、satisfyGeneralRules関数による絞り込み前のindex件数。
      countSatisfy    = 0;       // satisfyGeneralRules関数による絞り込み通過件数を0で初期化。
      for (i = 0; i < Rows; i++) {
         // DBから読み込んだ1件の指標データを一時的に変数に格納する。
         
         init_st_vOrderIndex(buf_st_vOrderIndex);// 一時的に値を格納する変数の初期化。

         if (MySqlCursorFetchRow(intCursor)) {
            // カーソルの指す1件を取得する。
            // 
            buf_st_vOrderIndex.symbol      = MySqlGetFieldAsString(intCursor, 0);
            buf_st_vOrderIndex.timeframe   = MySqlGetFieldAsInt(intCursor,    1);
            buf_st_vOrderIndex.calcTime    = MySqlGetFieldAsInt(intCursor,    2);
            buf_calc_dt_str = MySqlGetFieldAsString(intCursor, 3);
            
            buf_read_integer = MySqlGetFieldAsInt(intCursor, 4);
            buf_st_vOrderIndex.MA_GC = buf_read_integer;

            buf_read_integer = MySqlGetFieldAsInt(intCursor, 5);
            buf_st_vOrderIndex.MA_DC = buf_read_integer;

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 6);
            buf_st_vOrderIndex.MA_Slope5 = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 7);
            buf_st_vOrderIndex.MA_Slope25 = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 8);
            buf_st_vOrderIndex.MA_Slope75 = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 9);
            buf_st_vOrderIndex.BB_Width = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,10);
            buf_st_vOrderIndex.IK_TEN = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,11);
            buf_st_vOrderIndex.IK_CHI = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,12);
            buf_st_vOrderIndex.IK_LEG = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_integer = MySqlGetFieldAsInt(intCursor,13);
            buf_st_vOrderIndex.MACD_GC = buf_read_integer;

            buf_read_integer = MySqlGetFieldAsInt(intCursor,14);
            buf_st_vOrderIndex.MACD_DC = buf_read_integer;

            buf_read_double =  MySqlGetFieldAsInt(intCursor,15);
            buf_st_vOrderIndex.RSI_VAL= NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,16);
            buf_st_vOrderIndex.STOC_VAL= NormalizeDouble(buf_read_double, global_Digits);

            buf_read_integer = MySqlGetFieldAsInt(intCursor,17);
            buf_st_vOrderIndex.STOC_GC = buf_read_integer;

            buf_read_integer = MySqlGetFieldAsInt(intCursor,18);
            buf_st_vOrderIndex.STOC_DC = buf_read_integer;

            buf_read_double =  MySqlGetFieldAsInt(intCursor,19);
            buf_st_vOrderIndex.RCI_VAL= NormalizeDouble(buf_read_double, global_Digits);


            // satisfyGeneralRules関数を使って、読みだしたindextableテーブルデータがルールを満たしているかを確認し、
            // 条件を満たしていなければ、廃棄する。
            bool flag_satisfyGeneralRules = satisfyGeneralRules(buf_st_vOrderIndex, BS_PL_FLAG);
            if(flag_satisfyGeneralRules == false) {
               // 条件を満たさなかった時は、何もしない               
            }
            else {
               countSatisfy++; // satisfyGeneralRules関数を使った絞り込みを通過した件数を1増やす。

               // ルールを満たした指標（BUY/PROFIT等の条件を満たした取引を約定したときの指標）のため、
               // 各項目の値を平均、偏差計算用配列にコピーする。
               if(buf_st_vOrderIndex.MA_GC > INT_VALUE_MIN) {
                  DB_MA_GC_mData[DB_MA_GC_mDataNum] = buf_st_vOrderIndex.MA_GC;
                  DB_MA_GC_mDataNum++;
               }

               if(buf_st_vOrderIndex.MA_DC > INT_VALUE_MIN) {
                  DB_MA_DC_mData[DB_MA_DC_mDataNum] = buf_st_vOrderIndex.MA_DC;
                  DB_MA_DC_mDataNum++;
               }

               if(buf_st_vOrderIndex.MA_Slope5 > DOUBLE_VALUE_MIN) {
                  DB_MA_Slope5_mData[DB_MA_Slope5_mDataNum] = buf_st_vOrderIndex.MA_Slope5;
                  DB_MA_Slope5_mDataNum++;
               }

               if(buf_st_vOrderIndex.MA_Slope25 > DOUBLE_VALUE_MIN) {
                  DB_MA_Slope25_mData[DB_MA_Slope25_mDataNum] = buf_st_vOrderIndex.MA_Slope25;
                  DB_MA_Slope25_mDataNum++;
               }
 
               if(buf_st_vOrderIndex.MA_Slope75 > DOUBLE_VALUE_MIN) {
                  DB_MA_Slope75_mData[DB_MA_Slope75_mDataNum] = buf_st_vOrderIndex.MA_Slope75;
                  DB_MA_Slope75_mDataNum++;
               }

               if(buf_st_vOrderIndex.BB_Width > DOUBLE_VALUE_MIN) {
                  DB_BB_Width_mData[DB_BB_Width_mDataNum] = buf_st_vOrderIndex.BB_Width;
                  DB_BB_Width_mDataNum++;
               }

               if(buf_st_vOrderIndex.IK_TEN > DOUBLE_VALUE_MIN) {
                  DB_IK_TEN_mData[DB_IK_TEN_mDataNum] = buf_st_vOrderIndex.IK_TEN;
                  DB_IK_TEN_mDataNum++;
               }

               if(buf_st_vOrderIndex.IK_CHI > DOUBLE_VALUE_MIN) {
                  DB_IK_CHI_mData[DB_IK_CHI_mDataNum] = buf_st_vOrderIndex.IK_CHI;
                  DB_IK_CHI_mDataNum++;
               }

               if(buf_st_vOrderIndex.IK_LEG > DOUBLE_VALUE_MIN) {
                  DB_IK_LEG_mData[DB_IK_TEN_mDataNum] = buf_st_vOrderIndex.IK_LEG;
                  DB_IK_LEG_mDataNum++;
               }

               if(buf_st_vOrderIndex.MACD_GC > INT_VALUE_MIN) {
                  DB_MACD_GC_mData[DB_MACD_GC_mDataNum] = buf_st_vOrderIndex.MACD_GC;
                  DB_MACD_GC_mDataNum++;
               }

               if(buf_st_vOrderIndex.MACD_DC > INT_VALUE_MIN) {
                  DB_MACD_DC_mData[DB_MACD_DC_mDataNum] = buf_st_vOrderIndex.MACD_DC;
                  DB_MACD_DC_mDataNum++;
               }

               if(buf_st_vOrderIndex.RSI_VAL > DOUBLE_VALUE_MIN) {
                  DB_RSI_VAL_mData[DB_RSI_VAL_mDataNum] = buf_st_vOrderIndex.RSI_VAL;
                  DB_RSI_VAL_mDataNum++;
               }

               if(buf_st_vOrderIndex.STOC_VAL > DOUBLE_VALUE_MIN) {
                  DB_STOC_VAL_mData[DB_STOC_VAL_mDataNum] = buf_st_vOrderIndex.STOC_VAL;
                  DB_STOC_VAL_mDataNum++;
               }

               if(buf_st_vOrderIndex.STOC_GC > INT_VALUE_MIN) {
                  DB_STOC_GC_mData[DB_STOC_GC_mDataNum] = buf_st_vOrderIndex.STOC_GC;
                  DB_STOC_GC_mDataNum++;
               }

               if(buf_st_vOrderIndex.STOC_DC > INT_VALUE_MIN) {
                  DB_STOC_DC_mData[DB_STOC_DC_mDataNum] = buf_st_vOrderIndex.STOC_DC;
                  DB_STOC_DC_mDataNum++;
               }

               if(buf_st_vOrderIndex.RCI_VAL > DOUBLE_VALUE_MIN) {
                  DB_RCI_VAL_mData[DB_RCI_VAL_mDataNum] = buf_st_vOrderIndex.RCI_VAL;
                  DB_RCI_VAL_mDataNum++;
               }

            }
         }    //  if (MySqlCursorFetchRow(intCursor)) {

      }       // for (i=0; i<Rows; i++) {
//printf( "[%d]テスト　SELL_PROFITに該当する取引の約定時間におけるindex>%d<件に対して、satisfyGeneralRules通過は>%d<件" , __LINE__,
//         countSatisfyMAX,countSatisfy);
   }          // else
   MySqlCursorClose(intCursor);

bool testFlag_over3 = false;  // 実験用。1つでも3件以上のデータがあればtrueになる。
bool testFlag_calcOK = false;  // 実験用。1つでも平均、偏差を計算できていればtrueになる
   
   bool calcFlag = false; 
   if(DB_MA_GC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_GC_mData, DB_MA_GC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesSELL_Profit.MA_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.MA_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MA_GC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_MA_DC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_DC_mData, DB_MA_DC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesSELL_Profit.MA_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.MA_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MA_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_MA_Slope5_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_Slope5_mData, DB_MA_Slope5_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesSELL_Profit.MA_Slope5_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_Slope5_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.MA_Slope5_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MA_Slope5_SIGMA = DOUBLE_VALUE_MIN;
      }
   }
   
   if(DB_MA_Slope25_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_Slope25_mData, DB_MA_Slope25_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesSELL_Profit.MA_Slope25_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_Slope25_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.MA_Slope25_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MA_Slope25_SIGMA = DOUBLE_VALUE_MIN;
      }
   }
   
   if(DB_MA_Slope75_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_Slope75_mData, DB_MA_Slope75_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesSELL_Profit.MA_Slope75_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_Slope75_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.MA_Slope75_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MA_Slope75_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_BB_Width_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_BB_Width_mData, DB_BB_Width_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesSELL_Profit.BB_Width_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.BB_Width_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.BB_Width_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.BB_Width_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_IK_TEN_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_IK_TEN_mData, DB_IK_TEN_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesSELL_Profit.IK_TEN_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.IK_TEN_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.IK_TEN_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.IK_TEN_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_IK_CHI_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_IK_CHI_mData, DB_IK_CHI_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesSELL_Profit.IK_CHI_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.IK_CHI_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.IK_CHI_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.IK_CHI_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   
   
   if(DB_IK_LEG_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_IK_LEG_mData, DB_IK_LEG_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesSELL_Profit.IK_LEG_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.IK_LEG_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.IK_LEG_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.IK_LEG_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   

   if(DB_MACD_GC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MACD_GC_mData, DB_MA_GC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesSELL_Profit.MACD_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MACD_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.MACD_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MACD_GC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_MACD_DC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MACD_DC_mData, DB_MACD_DC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesSELL_Profit.MACD_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MACD_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.MACD_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MACD_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   
   
   if(DB_RSI_VAL_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_RSI_VAL_mData, DB_RSI_VAL_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesSELL_Profit.RSI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.RSI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.RSI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.RSI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }
   }      

   if(DB_STOC_VAL_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_STOC_VAL_mData, DB_STOC_VAL_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesSELL_Profit.STOC_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.STOC_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.STOC_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.STOC_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   

   if(DB_STOC_GC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_STOC_GC_mData, DB_MA_GC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesSELL_Profit.STOC_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.STOC_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.STOC_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.STOC_GC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_STOC_DC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_STOC_DC_mData, DB_STOC_DC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesSELL_Profit.STOC_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.STOC_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.STOC_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.STOC_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_RCI_VAL_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_RCI_VAL_mData, DB_RCI_VAL_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesSELL_Profit.RCI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.RCI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.RCI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.RCI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }
   }       

// showAnarizedIndex(st_vAnalyzedIndexesSELL_Profit);  // st_vAnalyzedIndexesSELL_Profitの各項目を出力する。

/*if(testFlag_over3 == true) {
printf( "[%d]テスト 1項目は3件以上のデータあり" , __LINE__);
}
else {
printf( "[%d]テスト 全項目3件未満" , __LINE__);
}
if(testFlag_calcOK == true) {
printf( "[%d]テスト 1項目は平均と偏差の計算成功" , __LINE__);
}
else {
printf( "[%d]テスト 全項目、平均と偏差の計算失敗" , __LINE__);
}*/

   // ここまでで、条件を満たす取引を約定したときのindextableテーブルデータを1件読み出せた。
   DB_insert_st_vAnalyzedIndexes(false, st_vAnalyzedIndexesSELL_Profit);  // falseは、バッファが一杯の時のみ書き込み。

        
   return true;
}


//+-----------------------------------------------------------------------------+
//| create_Stoc_vOrdersSELL_LOSSのDB対応版。
//+-----------------------------------------------------------------------------+
// 仮想取引を評価し、戦略別・通貨ペア別・タイムフレーム別・売買区分別・損益別の各指標の平均と偏差を計算する。
// 約定日が、引数mFROM_vOrder_openTimeから、mCalcTimeまでの約定とそれに紐づく指標データを平均、偏差の計算処理対象とする。
// 仮想取引が売り＋利益である時の指標の平均と偏差を計算する。
// 計算結果は、グローバル変数st_vAnalyzedIndexesSELL_Lossに入る。
bool DB_create_Stoc_vOrdersSELL_LOSS(int      mStageID,              // 入力：計算中のステージ番号
                                     string   mStrategyID,           // 入力：計算中の戦略名
                                     string   mSymbol,               // 入力：計算中の通貨ペア
                                     int      mTimeframe_calc,       // 入力： PERIOD_M15。指標を計算する時に使う時間軸
                                     datetime mCalcTime,             // 入力：計算基準時間。評価対象となる仮想取引の約定時間がこの時間まで。
                                     datetime mFROM_vOrder_openTime  // 入力：評価対象となる仮想取引の約定時間がこの値以降。
                                     ) {
   // 対象とする最初の時間が負の場合は、仮想取引の先頭から計算対象とする。
   if(mFROM_vOrder_openTime < 0) {
      mFROM_vOrder_openTime = 0;
   }

   if(mFROM_vOrder_openTime > mCalcTime) {
      printf( "[%d]テスト 計算対象取引の先頭時間%d:%sが末尾時間%d:%sより大きい" , __LINE__,
                mFROM_vOrder_openTime, TimeToStr(mFROM_vOrder_openTime),
                 mCalcTime, TimeToStr(mCalcTime));
      return false;
   }

   // キー項目の初期値を設定する
   st_vAnalyzedIndexesSELL_Loss.stageID     = mStageID;
   st_vAnalyzedIndexesSELL_Loss.strategyID  = mStrategyID;
   st_vAnalyzedIndexesSELL_Loss.symbol      = mSymbol;
   st_vAnalyzedIndexesSELL_Loss.timeframe   = mTimeframe_calc;
   st_vAnalyzedIndexesSELL_Loss.orderType   = OP_SELL;
   st_vAnalyzedIndexesSELL_Loss.PLFlag      = vLOSS; // vPL_DEFAULT=0, vPROFIT=1, vLOSS=-1
   st_vAnalyzedIndexesSELL_Loss.analyzeTime = mCalcTime;
    
   // 4種のどのパターンで処理をするか。
   int BS_PL_FLAG = vSELL_LOSS;

   if(StringLen(mStrategyID) <= 0) {
printf( "[%d]テスト 戦略名未設定" , __LINE__);
      return false;
   }
   if(StringLen(mSymbol) <= 0) {
printf( "[%d]テスト 通貨ペア未設定" , __LINE__);
      return false;
   }
   if(mTimeframe_calc < 0) {
printf( "[%d]テスト 時間軸未設定" , __LINE__);   
      return false;
   }


   int    Index_of_st_vOrderIndexes = -1;
   double indexMean  = 0.0;
   double indexSigma = 0.0;

   bool retFlag = false;  
   int    DB_MEAN_SIGMA_Num = 0;
   double DB_MEAN_SIGMA_Data[DB_VTRADENUM_MAX];
      
  //
  // １．売りかつ損失の仮想取引のオープン時各指標値は、ここから。
  //
  // 変数の初期化。平均と偏差を計算するための配列MA_GC_mData[i]などを初期化。
   DB_MEAN_SIGMA_Num = 0;
   ArrayInitialize(DB_MEAN_SIGMA_Data, 0.0);


   //    
   // ①売りかつ損失の仮想取引を検索する　→　副問い合わせtmpTableファイルに格納する。　　←　基準時間に近い約定ほど重みづけしたり、最近の数％件数のみを対象とするなど、工夫する。
   string Query = "";
   Query = Query + " SELECT symbol, openTime FROM vtradetable ";
   Query = Query + " where ";
   Query = Query + " stageID = " + IntegerToString(mStageID);
   Query = Query + " AND ";
   Query = Query + " strategyID = \'" + mStrategyID + "\'" ;
   Query = Query + " AND " ;
   Query = Query + " symbol = \'" + mSymbol + "\'" ;
   Query = Query + " AND "; 
   Query = Query + " orderType = " + IntegerToString(OP_SELL) ;
   Query = Query + " AND ( " ;
      
   // 約定日が、引数mFROM_vOrder_openTimeから、mCalcTimeまでの約定とそれに紐づく指標データを平均、偏差の計算処理対象とする。
   Query = Query + " ( (openTime >= " + IntegerToString(mFROM_vOrder_openTime) + " AND openTime <= " + IntegerToString(mCalcTime) + ") " ;
   Query = Query + "AND " ;
   

   // 決済損益の計算対象取引は、決済日closeTimeがmFROM_vOrder_openTimeとmCalcTimeの間にあること。決済損益closePL < 0.0であること。
   Query = Query + "(closeTime >= " + IntegerToString(mFROM_vOrder_openTime) + " AND closeTime <= " + IntegerToString(mCalcTime) + ") AND closePL < 0.0)";
   Query = Query + " OR ";   
   // 評価損益の計算対象取引は、決済日が0のままか、決済されていたとしても決済日closeTimeがmTO_vOrder_openTimeよりあとであること。評価日estimateTimeがmCalcTimeと同じかそれより前。評価損益estimatePL > 0.0であること。
   Query = Query + "( (estimateTime > 0 AND estimateTime <= " + IntegerToString(mCalcTime) + ") AND (closeTime = 0 OR closeTime > " + IntegerToString(mCalcTime) + ") AND estimatePL < 0.0))";

   // ②副問い合わせの戻り値Symbol, openTime(, timeframeは引数timeframeを使う）をキー項目として、平均と偏差の計算対象とする指標データを検索する。
   //  なお、indextable.calc_dtを使って降順に並び変えておく。計算対象がDB_VTRADENUM_MAX件以上になったとしても、影響力が大きいとみなせる最近の指標データを計算対象にできるため。
   // →上記①で求めた副問い合わせの前後に、indextableの検索をする部品を追加する。
   string preQuery = "";   
   preQuery = preQuery + " SELECT * FROM indextable ";
   preQuery = preQuery + " WHERE ";
   preQuery = preQuery + " timeframe = "+ IntegerToString(mTimeframe_calc);
   preQuery = preQuery + " AND ";
   preQuery = preQuery + " (symbol, calc_dt) = ";
   preQuery = preQuery + " ANY(SELECT * FROM ( ";
   
   //
   // indextable検索用部品preQueryに、副問い合わせQueryに結合する
   Query = preQuery + Query;   
   //
   // 副問い合わせの末尾を結合
   Query = Query + " ) AS temp1) ORDER BY calc_dt DESC;";

   sqlGetIndexSellLoss = "";
   sqlGetIndexSellLoss = sqlGetIndexSellLoss + " SELECT " + IntegerToString(mStageID) + ", " + IntegerToString(OP_SELL) + ", " + IntegerToString(vLOSS) + ", * FROM indextable ";
   sqlGetIndexSellLoss = sqlGetIndexSellLoss + " WHERE ";
   sqlGetIndexSellLoss = sqlGetIndexSellLoss + " timeframe = "+ IntegerToString(mTimeframe_calc);
   sqlGetIndexSellLoss = sqlGetIndexSellLoss + " AND ";
   sqlGetIndexSellLoss = sqlGetIndexSellLoss + " (symbol, calc_dt) = ";
   sqlGetIndexSellLoss = sqlGetIndexSellLoss + " ANY(SELECT * FROM ( ";
   sqlGetIndexSellLoss = sqlGetIndexSellLoss + Query + " ) AS temp1) ORDER BY calc_dt DESC;";

 //  printf("[%d]テスト 実験中SELL_LOSSな仮想取引の約定時間におけるindexを検索：%s" , __LINE__, sqlGetIndexSellLoss);   
 //printf("[%d]テスト SELL_LOSSな仮想取引の約定時間におけるindexを検索：%s" , __LINE__, Query);

   int i;
   string buf_symbol = "";
   int    buf_timeframe = 0;
   int    buf_calc_dt = 0;
   string buf_calc_dt_str = "";
   
   int    buf_read_integer = 0;
   double buf_read_double  = 0.0;
   int    countSatisfy    = 0; // satisfyGeneralRules関数で条件を満たしたindexテーブルの個数
   int    countSatisfyMAX = 0; // satisfyGeneralRules関数の判定対象としてindexテーブルの総数

   init_Mean_Sig_Variables();  // 平均、偏差を計算するためのデータを格納する配列及びデータ個数を示す変数を初期化する。
   int intCursor = MySqlCursorOpen(DB, Query);

   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);              
   }
   else {
      int Rows = MySqlCursorRows(intCursor);
//printf( "[%d]テスト　計算基準時間%sのSELL_LOSSに該当する取引の約定時間におけるindex件数:%d件%s" , __LINE__, TimeToStr(mCalcTime), Rows, Query);              

      st_vOrderIndex buf_st_vOrderIndex;   // indextableテーブルから1行読み込んだデータを一時的に保存する。
      countSatisfyMAX = Rows;    // SELL_LOSSに該当する取引の約定時間におけるindex件数。かつ、satisfyGeneralRules関数による絞り込み前のindex件数。
      countSatisfy    = 0;       // satisfyGeneralRules関数による絞り込み通過件数を0で初期化。
      for (i = 0; i < Rows; i++) {
         // DBから読み込んだ1件の指標データを一時的に変数に格納する。
         
         init_st_vOrderIndex(buf_st_vOrderIndex);// 一時的に値を格納する変数の初期化。

         if (MySqlCursorFetchRow(intCursor)) {
            // カーソルの指す1件を取得する。
            // 
            buf_st_vOrderIndex.symbol      = MySqlGetFieldAsString(intCursor, 0);
            buf_st_vOrderIndex.timeframe   = MySqlGetFieldAsInt(intCursor,    1);
            buf_st_vOrderIndex.calcTime    = MySqlGetFieldAsInt(intCursor,    2);
            buf_calc_dt_str = MySqlGetFieldAsString(intCursor, 3);
            
            buf_read_integer = MySqlGetFieldAsInt(intCursor, 4);
            buf_st_vOrderIndex.MA_GC = buf_read_integer;

            buf_read_integer = MySqlGetFieldAsInt(intCursor, 5);
            buf_st_vOrderIndex.MA_DC = buf_read_integer;

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 6);
            buf_st_vOrderIndex.MA_Slope5 = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 7);
            buf_st_vOrderIndex.MA_Slope25 = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 8);
            buf_st_vOrderIndex.MA_Slope75 = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor, 9);
            buf_st_vOrderIndex.BB_Width = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,10);
            buf_st_vOrderIndex.IK_TEN = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,11);
            buf_st_vOrderIndex.IK_CHI = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,12);
            buf_st_vOrderIndex.IK_LEG = NormalizeDouble(buf_read_double, global_Digits);

            buf_read_integer = MySqlGetFieldAsInt(intCursor,13);
            buf_st_vOrderIndex.MACD_GC = buf_read_integer;

            buf_read_integer = MySqlGetFieldAsInt(intCursor,14);
            buf_st_vOrderIndex.MACD_DC = buf_read_integer;

            buf_read_double =  MySqlGetFieldAsInt(intCursor,15);
            buf_st_vOrderIndex.RSI_VAL= NormalizeDouble(buf_read_double, global_Digits);

            buf_read_double =  MySqlGetFieldAsInt(intCursor,16);
            buf_st_vOrderIndex.STOC_VAL= NormalizeDouble(buf_read_double, global_Digits);

            buf_read_integer = MySqlGetFieldAsInt(intCursor,17);
            buf_st_vOrderIndex.STOC_GC = buf_read_integer;

            buf_read_integer = MySqlGetFieldAsInt(intCursor,18);
            buf_st_vOrderIndex.STOC_DC = buf_read_integer;

            buf_read_double =  MySqlGetFieldAsInt(intCursor,19);
            buf_st_vOrderIndex.RCI_VAL= NormalizeDouble(buf_read_double, global_Digits);


            // satisfyGeneralRules関数を使って、読みだしたindextableテーブルデータがルールを満たしているかを確認し、
            // 条件を満たしていなければ、廃棄する。
            bool flag_satisfyGeneralRules = satisfyGeneralRules(buf_st_vOrderIndex, BS_PL_FLAG);
            if(flag_satisfyGeneralRules == false) {
               // 条件を満たさなかった時は、何もしない               
            }
            else {
               countSatisfy++; // satisfyGeneralRules関数を使った絞り込みを通過した件数を1増やす。

               // ルールを満たした指標（BUY/PROFIT等の条件を満たした取引を約定したときの指標）のため、
               // 各項目の値を平均、偏差計算用配列にコピーする。
               if(buf_st_vOrderIndex.MA_GC > INT_VALUE_MIN) {
                  DB_MA_GC_mData[DB_MA_GC_mDataNum] = buf_st_vOrderIndex.MA_GC;
                  DB_MA_GC_mDataNum++;
               }

               if(buf_st_vOrderIndex.MA_DC > INT_VALUE_MIN) {
                  DB_MA_DC_mData[DB_MA_DC_mDataNum] = buf_st_vOrderIndex.MA_DC;
                  DB_MA_DC_mDataNum++;
               }

               if(buf_st_vOrderIndex.MA_Slope5 > DOUBLE_VALUE_MIN) {
                  DB_MA_Slope5_mData[DB_MA_Slope5_mDataNum] = buf_st_vOrderIndex.MA_Slope5;
                  DB_MA_Slope5_mDataNum++;
               }

               if(buf_st_vOrderIndex.MA_Slope25 > DOUBLE_VALUE_MIN) {
                  DB_MA_Slope25_mData[DB_MA_Slope25_mDataNum] = buf_st_vOrderIndex.MA_Slope25;
                  DB_MA_Slope25_mDataNum++;
               }
 
               if(buf_st_vOrderIndex.MA_Slope75 > DOUBLE_VALUE_MIN) {
                  DB_MA_Slope75_mData[DB_MA_Slope75_mDataNum] = buf_st_vOrderIndex.MA_Slope75;
                  DB_MA_Slope75_mDataNum++;
               }

               if(buf_st_vOrderIndex.BB_Width > DOUBLE_VALUE_MIN) {
                  DB_BB_Width_mData[DB_BB_Width_mDataNum] = buf_st_vOrderIndex.BB_Width;
                  DB_BB_Width_mDataNum++;
               }

               if(buf_st_vOrderIndex.IK_TEN > DOUBLE_VALUE_MIN) {
                  DB_IK_TEN_mData[DB_IK_TEN_mDataNum] = buf_st_vOrderIndex.IK_TEN;
                  DB_IK_TEN_mDataNum++;
               }

               if(buf_st_vOrderIndex.IK_CHI > DOUBLE_VALUE_MIN) {
                  DB_IK_CHI_mData[DB_IK_CHI_mDataNum] = buf_st_vOrderIndex.IK_CHI;
                  DB_IK_CHI_mDataNum++;
               }

               if(buf_st_vOrderIndex.IK_LEG > DOUBLE_VALUE_MIN) {
                  DB_IK_LEG_mData[DB_IK_TEN_mDataNum] = buf_st_vOrderIndex.IK_LEG;
                  DB_IK_LEG_mDataNum++;
               }

               if(buf_st_vOrderIndex.MACD_GC > INT_VALUE_MIN) {
                  DB_MACD_GC_mData[DB_MACD_GC_mDataNum] = buf_st_vOrderIndex.MACD_GC;
                  DB_MACD_GC_mDataNum++;
               }

               if(buf_st_vOrderIndex.MACD_DC > INT_VALUE_MIN) {
                  DB_MACD_DC_mData[DB_MACD_DC_mDataNum] = buf_st_vOrderIndex.MACD_DC;
                  DB_MACD_DC_mDataNum++;
               }

               if(buf_st_vOrderIndex.RSI_VAL > DOUBLE_VALUE_MIN) {
                  DB_RSI_VAL_mData[DB_RSI_VAL_mDataNum] = buf_st_vOrderIndex.RSI_VAL;
                  DB_RSI_VAL_mDataNum++;
               }

               if(buf_st_vOrderIndex.STOC_VAL > DOUBLE_VALUE_MIN) {
                  DB_STOC_VAL_mData[DB_STOC_VAL_mDataNum] = buf_st_vOrderIndex.STOC_VAL;
                  DB_STOC_VAL_mDataNum++;
               }

               if(buf_st_vOrderIndex.STOC_GC > INT_VALUE_MIN) {
                  DB_STOC_GC_mData[DB_STOC_GC_mDataNum] = buf_st_vOrderIndex.STOC_GC;
                  DB_STOC_GC_mDataNum++;
               }

               if(buf_st_vOrderIndex.STOC_DC > INT_VALUE_MIN) {
                  DB_STOC_DC_mData[DB_STOC_DC_mDataNum] = buf_st_vOrderIndex.STOC_DC;
                  DB_STOC_DC_mDataNum++;
               }

               if(buf_st_vOrderIndex.RCI_VAL > DOUBLE_VALUE_MIN) {
                  DB_RCI_VAL_mData[DB_RCI_VAL_mDataNum] = buf_st_vOrderIndex.RCI_VAL;
                  DB_RCI_VAL_mDataNum++;
               }

            }
         }    //  if (MySqlCursorFetchRow(intCursor)) {

      }       // for (i=0; i<Rows; i++) {
//printf( "[%d]テスト　SELL_LOSSに該当する取引の約定時間におけるindex>%d<件に対して、satisfyGeneralRules通過は>%d<件" , __LINE__,
 //        countSatisfyMAX,countSatisfy);
   }          // else
   MySqlCursorClose(intCursor);

bool testFlag_over3 = false;  // 実験用。1つでも3件以上のデータがあればtrueになる。
bool testFlag_calcOK = false;  // 実験用。1つでも平均、偏差を計算できていればtrueになる
   
   bool calcFlag = false; 
   if(DB_MA_GC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_GC_mData, DB_MA_GC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesSELL_Loss.MA_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.MA_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MA_GC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_MA_DC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_DC_mData, DB_MA_DC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesSELL_Loss.MA_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.MA_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MA_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_MA_Slope5_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_Slope5_mData, DB_MA_Slope5_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesSELL_Loss.MA_Slope5_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_Slope5_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.MA_Slope5_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MA_Slope5_SIGMA = DOUBLE_VALUE_MIN;
      }
   }
   
   if(DB_MA_Slope25_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_Slope25_mData, DB_MA_Slope25_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesSELL_Loss.MA_Slope25_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_Slope25_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.MA_Slope25_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MA_Slope25_SIGMA = DOUBLE_VALUE_MIN;
      }
   }
   
   if(DB_MA_Slope75_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MA_Slope75_mData, DB_MA_Slope75_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesSELL_Loss.MA_Slope75_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_Slope75_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.MA_Slope75_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MA_Slope75_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_BB_Width_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_BB_Width_mData, DB_BB_Width_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
         st_vAnalyzedIndexesSELL_Loss.BB_Width_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.BB_Width_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.BB_Width_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.BB_Width_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_IK_TEN_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_IK_TEN_mData, DB_IK_TEN_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesSELL_Loss.IK_TEN_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.IK_TEN_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.IK_TEN_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.IK_TEN_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_IK_CHI_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_IK_CHI_mData, DB_IK_CHI_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesSELL_Loss.IK_CHI_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.IK_CHI_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.IK_CHI_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.IK_CHI_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   
   
   if(DB_IK_LEG_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_IK_LEG_mData, DB_IK_LEG_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesSELL_Loss.IK_LEG_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.IK_LEG_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.IK_LEG_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.IK_LEG_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   

   if(DB_MACD_GC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MACD_GC_mData, DB_MA_GC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
testFlag_calcOK= true;      
      
         st_vAnalyzedIndexesSELL_Loss.MACD_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MACD_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.MACD_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MACD_GC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_MACD_DC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_MACD_DC_mData, DB_MACD_DC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesSELL_Loss.MACD_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MACD_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.MACD_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MACD_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   
   
   if(DB_RSI_VAL_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_RSI_VAL_mData, DB_RSI_VAL_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesSELL_Loss.RSI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.RSI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.RSI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.RSI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }
   }      

   if(DB_STOC_VAL_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_STOC_VAL_mData, DB_STOC_VAL_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesSELL_Loss.STOC_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.STOC_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.STOC_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.STOC_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }
   }   

   if(DB_STOC_GC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_STOC_GC_mData, DB_MA_GC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesSELL_Loss.STOC_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.STOC_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.STOC_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.STOC_GC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_STOC_DC_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_STOC_DC_mData, DB_STOC_DC_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesSELL_Loss.STOC_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.STOC_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.STOC_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.STOC_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
   }

   if(DB_RCI_VAL_mDataNum > 3) {
testFlag_over3 = true;   
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;   
      calcFlag = calcMeanAndSigma(DB_RCI_VAL_mData, DB_RCI_VAL_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
      testFlag_calcOK= true;      

         st_vAnalyzedIndexesSELL_Loss.RCI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.RCI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.RCI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.RCI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }
   }       

// showAnarizedIndex(st_vAnalyzedIndexesSELL_Loss);  // st_vAnalyzedIndexesSELL_Lossの各項目を出力する。

/*if(testFlag_over3 == true) {
printf( "[%d]テスト 1項目は3件以上のデータあり" , __LINE__);
}
else {
printf( "[%d]テスト 全項目3件未満" , __LINE__);
}
if(testFlag_calcOK == true) {
printf( "[%d]テスト 1項目は平均と偏差の計算成功" , __LINE__);
}
else {
printf( "[%d]テスト 全項目、平均と偏差の計算失敗" , __LINE__);
}*/

   // ここまでで、条件を満たす取引を約定したときのindextableテーブルデータを1件読み出せた。
   DB_insert_st_vAnalyzedIndexes(false, st_vAnalyzedIndexesSELL_Loss);  // falseは、バッファが一杯の時のみ書き込み。

        
   return true;
}




// 4指標の値st_BS_PLをvAnalyzedIndexテーブルに書き出す。
// バッファinsBuffer_st_vAnalyzedIndex[VTRADENUM_MAX]が満杯近くになるまで、
// バッファに登録する。
// blWriteAllがtrueの時は、バッファの空きによらず、バッファのデータを書き出す。
// blWriteAllがfalseの時は、バッファの空きが10件未満もしくは、使用率が95%を超えた時にバッファのデータを書き出す。
// st_vAnalyzedIndexesBUY_Profit;  // 買いで利益が出た仮想取引を対象とした指標の分析結果。
// st_vAnalyzedIndexesBUY_Loss;    // 買いで損失が出た仮想取引を対象とした指標の分析結果。
// st_vAnalyzedIndexesSELL_Profit; // 売りで利益が出た仮想取引を対象とした指標の分析結果。
// st_vAnalyzedIndexesSELL_Loss;   // 売りで損失が出た仮想取引を対象とした指標の分析結果。
// 登録に成功したらtrue, 失敗したらfalseを返す。
bool DB_insert_st_vAnalyzedIndexes(bool blWriteAll,             // trueの時、バッファの空きによらず、バッファのデータを書き出す
                                st_vAnalyzedIndex &st_BS_PL  // vAnarizedIndeテーブルに書き出すグローバル変数のいずれか。
                                ) {
//printf( "[%d]テスト　insert_st_vAnalyzedIndexes開始" , __LINE__);

   bool exstFlag = false; // DBに、引数st_BS_PLと同じst_vAnalyzedIndexデータがあれば、true。
   bool errFlag  = true;  // 不具合があれば、false。


   // 引数st_BS_PLをバッファに追加する。失敗すれば、バッファへの追加はあきらめるが、DB書き出し処理は続ける
   bool addBuf_flag = addBuffer_st_vAnalyzedIndex(st_BS_PL);
   if(addBuf_flag == false) {
// printf( "[%d]テスト　バッファに登録失敗" , __LINE__);   
   }


   //
   // 以降は、バッファinsBuffer_st_vAnalyzedIndex[VTRADENUM_MAX]内データのDB書き込み処理
   // → 引数blWriteAllがtrueか、バッファinsBuffer_st_vAnalyzedIndexの登録済み件数が多い時にDB書き込みする。
   // 


   // バッファinsBuffer_st_vAnalyzedIndex[VTRADENUM_MAX]に登録された有効なデータ数を取得する。
   int num_insBuffer_st_vAnalyzedIndex = get_st_vAnalyzedIndexNum(insBuffer_st_vAnalyzedIndex);

   bool flagWriteALL = false;  // trueの時、バッファ内の値をDBに書き出す。
   
   // 引数blWriteAllがtrueの場合は、バッファ内のデータを書き出す
   if(blWriteAll == true) {
      flagWriteALL = true;
   }
   else {
      // 引数blWriteAllがtrueでなくとも、バッファをある程度使っていたらバッファ内のデータを書き出す。
      if( num_insBuffer_st_vAnalyzedIndex > VTRADENUM_MAX - 10 
          || num_insBuffer_st_vAnalyzedIndex > VTRADENUM_MAX * 0.95){
         flagWriteALL = true;
      }
      // 引数blWriteAllがtrueでなく、バッファをある程度まで使っていなかったら、バッファにのみデータを書き出す。
      else {
         flagWriteALL = false;
      }
   }

   
   if(flagWriteALL == true) {
      // 以下はDB出力処理    
      int buf_count = 0;
      //
      // バッファinsBuffer_st_vAnalyzedIndex[VTRADENUM_MAX]の中で、意味のあるデータを読み込む
      //
      for(buf_count = 0; buf_count < VTRADENUM_MAX; buf_count++) {
         st_vAnalyzedIndex insBuffer = insBuffer_st_vAnalyzedIndex[buf_count];
         
         // 1件読み込んだinsBufferのキー項目が、正常の場合のみ処理をする。
         if(insBuffer.stageID >= 0
            && StringLen(insBuffer.strategyID) > 0
            && StringLen(insBuffer.symbol) > 0
            && insBuffer.timeframe >= 0 
            && ( insBuffer.orderType == OP_BUY  || insBuffer.orderType == OP_SELL) 
            && ( insBuffer.PLFlag == vPROFIT    || insBuffer.PLFlag == vLOSS) 
            && insBuffer.analyzeTime > 0 ) {
            //
            // DB内データの変更処理
            // 

            // 関数exist_vAnalyzedIndexesを使ってテーブル上に存在するかを確認。
            exstFlag = DB_exist_vAnalyzedIndexes(insBuffer);
      
            // 存在すれば、deleteする。そのあとは、存在しない場合と同様にinsertする。
            if(exstFlag == true) {
               errFlag = DB_delete_vAnalyzedIndex(
                                     insBuffer.stageID,    // ステージ番号。負の時は、ステージ番号を削除条件に加えない。
                                     insBuffer.strategyID, // 戦略名。　　　長さ0の時は、戦略名を削除条件に加えない。
                                     insBuffer.symbol,     // 仮想取引の通貨ペア。長さ0の時は、戦略名を削除条件に加えない。
                                     insBuffer.timeframe,  // 指標計算時の時間軸。15分足のデータを使って指標を計算していれば、PERIOD_M15。負の時は、削除条件に加えない。
                                     insBuffer.orderType,  // 売買区分。　　OP_BUY及びOP_SELL以外の時は、削除条件に加えない。
                                     insBuffer.PLFlag,     // 損益区分。vPROFIT, vLOSS以外の時は、削除条件に加えない。
                                     insBuffer.analyzeTime // 平均、偏差計算時の基準時間。負の時は、削除条件に加えない。
                                     ); 
            }
   
            // 存在するのに削除できなかったことから、以降のinsert文は実行しない。
            if(errFlag == false) {
//printf( "[%d]テスト vAnalyzedIndexが存在するのに削除できなかった" , __LINE__, DoubleToString(insBuffer.MA_GC_MEAN, global_Digits));
            
               // DB登録処理はしない。elseより下のバッファからのデータ削除はする。
            }
            else {   // errFlag == true つまり、既存データをvAnalyzedIndexテーブルから削除成功
/*
printf( "[%d]テスト バッファを書き出す対象 stageID=%d 戦略名=%s 通貨ペア=%s 時間軸=%d 売買=%d 損益=%d 時刻=%d::%s" , __LINE__, 
         insBuffer.stageID,
         insBuffer.strategyID,
         insBuffer.symbol,
         insBuffer.timeframe,  
         insBuffer.orderType,
         insBuffer.PLFlag,
         insBuffer.analyzeTime, TimeToStr(insBuffer.analyzeTime));
*/

               // insert文による新規追加/
               string insQuery = "";
               insQuery = "INSERT INTO `vAnalyzedIndex` (";
               insQuery = insQuery + " stageID, strategyID, symbol, timeframe, orderType, PLFlag, analyzeTime, analyzeTime_str, ";
               insQuery = insQuery + " MA_GC_MEAN,MA_GC_SIGMA,MA_DC_MEAN,MA_DC_SIGMA, ";
               insQuery = insQuery + " MA_Slope5_MEAN, MA_Slope5_SIGMA, ";
               insQuery = insQuery + " MA_Slope25_MEAN, MA_Slope25_SIGMA, ";
               insQuery = insQuery + " MA_Slope75_MEAN, MA_Slope75_SIGMA, ";
               insQuery = insQuery + " BB_Width_MEAN, BB_Width_SIGMA, "; 
               insQuery = insQuery + " IK_TEN_MEAN, IK_TEN_SIGMA, ";
               insQuery = insQuery + " IK_CHI_MEAN, IK_CHI_SIGMA, ";
               insQuery = insQuery + " IK_LEG_MEAN, IK_LEG_SIGMA, ";
               insQuery = insQuery + " MACD_GC_MEAN, MACD_GC_SIGMA, ";
               insQuery = insQuery + " MACD_DC_MEAN, MACD_DC_SIGMA, ";
               insQuery = insQuery + " RSI_VAL_MEAN, RSI_VAL_SIGMA, ";
               insQuery = insQuery + " STOC_VAL_MEAN, STOC_VAL_SIGMA, ";
               insQuery = insQuery + " STOC_GC_MEAN, STOC_GC_SIGMA, ";
               insQuery = insQuery + " STOC_DC_MEAN, STOC_DC_SIGMA, ";
               insQuery = insQuery + " RCI_VAL_MEAN, RCI_VAL_SIGMA ";
               insQuery = insQuery + " ) VALUES ( ";
               insQuery = insQuery + IntegerToString(insBuffer.stageID) +" ,"; // stageID
               insQuery = insQuery + "\'" + insBuffer.strategyID + "\', "; // strategyID
               insQuery = insQuery + "\'" + insBuffer.symbol + "\', "; // symbol 
               insQuery = insQuery + IntegerToString(insBuffer.timeframe) +" ,"; // timeframe 
               insQuery = insQuery + IntegerToString(insBuffer.orderType) +" ,"; // orderType 
               insQuery = insQuery + IntegerToString(insBuffer.PLFlag) +" ,"; // PLFlag 
               insQuery = insQuery + IntegerToString(insBuffer.analyzeTime) +" ,"; // 
               insQuery = insQuery + "\'" +TimeToStr(insBuffer.analyzeTime) + "\'" +" ,"; //    
               insQuery = insQuery + DoubleToStr(insBuffer.MA_GC_MEAN, global_Digits) +" ,"; // MA_GC_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.MA_GC_SIGMA, global_Digits) +" ,"; // MA_GC_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.MA_DC_MEAN, global_Digits) +" ,"; // MA_DC_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.MA_DC_SIGMA, global_Digits) +" ,"; // MA_DC_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.MA_Slope5_MEAN, global_Digits) +" ,"; // MA_Slope5_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.MA_Slope5_SIGMA, global_Digits) +" ,"; // MA_Slope5_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.MA_Slope25_MEAN, global_Digits) +" ,"; // MA_Slope25_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.MA_Slope25_SIGMA, global_Digits) +" ,"; // MA_Slope25_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.MA_Slope75_MEAN, global_Digits) +" ,"; // MA_Slope75_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.MA_Slope75_SIGMA, global_Digits) +" ,"; // MA_Slope75_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.BB_Width_MEAN, global_Digits) +" ,"; // BB_Width_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.BB_Width_SIGMA, global_Digits) +" ,"; // BB_Width_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.IK_TEN_MEAN, global_Digits) +" ,"; // IK_TEN_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.IK_TEN_SIGMA, global_Digits) +" ,"; // IK_TEN_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.IK_CHI_MEAN, global_Digits) +" ,"; // IK_CHI_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.IK_CHI_SIGMA, global_Digits) +" ,"; // IK_CHI_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.IK_LEG_MEAN, global_Digits) +" ,"; // IK_LEG_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.IK_LEG_SIGMA, global_Digits) +" ,"; // IK_LEG_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.MACD_GC_MEAN, global_Digits) +" ,"; // MACD_GC_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.MACD_GC_SIGMA, global_Digits) +" ,"; // MACD_GC_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.MACD_DC_MEAN, global_Digits) +" ,"; // MACD_DC_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.MACD_DC_SIGMA, global_Digits) +" ,"; // MACD_DC_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.RSI_VAL_MEAN, global_Digits) +" ,"; // RSI_VAL_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.RSI_VAL_SIGMA, global_Digits) +" ,"; // RSI_VAL_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.STOC_VAL_MEAN, global_Digits) +" ,"; // STOC_VAL_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.STOC_VAL_SIGMA, global_Digits) +" ,"; // STOC_VAL_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.STOC_GC_MEAN, global_Digits) +" ,"; // STOC_GC_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.STOC_GC_SIGMA, global_Digits) +" ,"; // STOC_GC_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.STOC_DC_MEAN, global_Digits) +" ,"; // STOC_DC_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.STOC_DC_SIGMA, global_Digits) +" ,"; // STOC_DC_SIGMA
               insQuery = insQuery + DoubleToStr(insBuffer.RCI_VAL_MEAN, global_Digits) +" ,"; // RCI_VAL_MEAN
               insQuery = insQuery + DoubleToStr(insBuffer.RCI_VAL_SIGMA, global_Digits) +""; // RCI_VAL_SIGMA
               insQuery = insQuery + ")";

//printf( "[%d]テスト　vAnalyzedIndexテーブルへのinsertSQL:%s" , __LINE__, insQuery);
        
               //SQL文を実行
               if (MySqlExecute(DB, insQuery) == true) {
                }
               else {
                  printf( "[%d]エラー　追加失敗:%s" , __LINE__, MySqlErrorDescription);                 
                  printf( "[%d]エラー　追加失敗時のSQL:%s" , __LINE__, insQuery);                 
                  errFlag = false;
               }   
            }   // else {   // errFlag == true つまり、既存データをvAnalyzedIndexテーブルから削除成功

            // vAnalyzedIndexテーブルへの登録成否によらず、
            // バッファinsBuffer_st_vAnalyzedIndex[VTRADENUM_MAX]から
            // 処理対象データinsBuffer_st_vAnalyzedIndex[buf_count]を削除する。
            // ↑今回登録できなかったデータは、将来も登録できない
            delete_Buffer_st_vAnalyzedIndex(buf_count);
         }
         else {

            delete_Buffer_st_vAnalyzedIndex(buf_count);
         }
      }                        
   }
   return true;
}



// バッファinsBuffer_st_vAnalyzedIndex[VTRADENUM_MAX]の空き領域に
// 引数st_vAnalyzedIndex &st_A_Indexを代入する。
bool  addBuffer_st_vAnalyzedIndex(st_vAnalyzedIndex &st_A_Index) {
   int i;
   int addedIndex = -1;

   // 登録対象であるst_A_Indexのデータ確認
   if(st_A_Index.stageID < 0) {
//printf( "[%d]テスト　ステージ番号が、未設定" , __LINE__);
   }
   if(StringLen(st_A_Index.strategyID) <= 0) {
//printf( "[%d]テスト　戦略名が、未設定　>%s<" , __LINE__, st_A_Index.strategyID);
   }
   if(StringLen(st_A_Index.symbol) <= 0) {
//printf( "[%d]テスト　通貨ペアが、未設定" , __LINE__);   
   }
   if(st_A_Index.timeframe <= 0) {
//printf( "[%d]テスト　時間軸が、未設定" , __LINE__);   
   }
   if(st_A_Index.orderType != OP_BUY && st_A_Index.orderType != OP_SELL) {
//printf( "[%d]テスト　オーダータイプが、未設定=%d" , __LINE__, st_A_Index.orderType);   
   } 
   if(st_A_Index.PLFlag != vPROFIT && st_A_Index.PLFlag != vLOSS) {
//printf( "[%d]テスト　損益フラグが、未設定=%d" , __LINE__, st_A_Index.orderType);   
   } 

   

   // 引数st_vAnalyzedIndex　st_A_Indexの全ての項目がDOUBLE_VALUE_MINの時は、false
   if(isOK_st_vAnalyzedIndex(st_A_Index) == false) {
//printf( "[%d]テスト バッファinsBuffer_st_vAnalyzedIndexへの追加候補がすべて異常値" , __LINE__);
      return false;
   }
   else {
/*printf( "[%d]テスト　ステージ番号=%d 戦略名=%s 通貨ペア=%s 時間軸=%d　売買区分=%d 損益フラグ=%d" , 
         __LINE__, 
         st_A_Index.stageID,
         st_A_Index.strategyID,
         st_A_Index.symbol,
         st_A_Index.timeframe,
         st_A_Index.orderType,
         st_A_Index.PLFlag);   */
   
   }
   
   for(i = 0; i < VTRADENUM_MAX; i++) {
      // キー項目が不正な項目は空きとみなす。
      if(insBuffer_st_vAnalyzedIndex[i].stageID < 0
         || StringLen(insBuffer_st_vAnalyzedIndex[i].symbol) <= 0
         || StringLen(insBuffer_st_vAnalyzedIndex[i].strategyID) <= 0 ) {
         addedIndex = i;
         break;
      }
   }
   

   if(addedIndex >= 0) {
      insBuffer_st_vAnalyzedIndex[addedIndex] = st_A_Index;
      
//****//
/*
      string testSymbol1 = st_A_Index.symbol;
      string testSymbol2 = insBuffer_st_vAnalyzedIndex[addedIndex].symbol;
      printf("[%d]実験 コピー元=%s  コピー先=%s", __LINE__, st_A_Index.symbol, insBuffer_st_vAnalyzedIndex[addedIndex].symbol);
st_A_Index.symbol = "testtest";
      printf("[%d]実験 コピー元修正後は泣き別れ？=%s  コピー先=%s", __LINE__, st_A_Index.symbol, insBuffer_st_vAnalyzedIndex[addedIndex].symbol);
st_A_Index.symbol = testSymbol1;
*/
//****//
      
      
      return true;
   }
   else {
      printf("[%d]エラー　バッファinsBuffer_st_vAnalyzedIndex[VTRADENUM_MAX]への追加失敗", __LINE__);
   
   }
   return false;   
}



bool isOK_st_vAnalyzedIndex(st_vAnalyzedIndex &st_A_Index) {
   // 引数st_vAnalyzedIndexは、キー項目が意味ない場合は、各項目の値によらずNG
   if(st_A_Index.stageID < 0
      || StringLen(st_A_Index.symbol) <= 0
      || StringLen(st_A_Index.strategyID) <= 0
      || st_A_Index.timeframe < 0
      || (st_A_Index.orderType != OP_BUY && st_A_Index.orderType != OP_SELL)
      || (st_A_Index.PLFlag != vPROFIT && st_A_Index.PLFlag != vLOSS)
       ) {
/*
         // 登録対象であるst_A_Indexのデータ確認
         if(st_A_Index.stageID < 0) {
printf( "[%d]テスト　ステージ番号が、未設定" , __LINE__);
         }
         if(StringLen(st_A_Index.strategyID) <= 0) {
printf( "[%d]テスト　戦略名が、未設定　>%s<" , __LINE__, st_A_Index.strategyID);
         }
         if(StringLen(st_A_Index.symbol) <= 0) {
printf( "[%d]テスト　通貨ペアが、未設定" , __LINE__);   
         }
         if(st_A_Index.timeframe <= 0) {
printf( "[%d]テスト　時間軸が、未設定" , __LINE__);   
         }
         if(st_A_Index.orderType != OP_BUY && st_A_Index.orderType != OP_SELL) {
printf( "[%d]テスト　オーダータイプが、未設定=%d" , __LINE__, st_A_Index.orderType);   
         } 
         if(st_A_Index.PLFlag != vPROFIT && st_A_Index.PLFlag != vLOSS) {
printf( "[%d]テスト　損益フラグが、未設定=%d" , __LINE__, st_A_Index.orderType);   
         } 
*/          
      return false;
   }
   if(   NormalizeDouble(st_A_Index.MA_GC_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MA_GC_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MA_GC_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MA_DC_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MA_DC_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MA_Slope5_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MA_Slope5_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MA_Slope25_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MA_Slope25_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MA_Slope75_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MA_Slope75_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.BB_Width_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.BB_Width_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.IK_TEN_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.IK_TEN_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.IK_CHI_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.IK_CHI_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.IK_LEG_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.IK_LEG_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MACD_GC_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MACD_GC_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MACD_DC_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.MACD_DC_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.RSI_VAL_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.RSI_VAL_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.STOC_VAL_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.STOC_VAL_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.STOC_GC_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.STOC_GC_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.STOC_DC_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.STOC_DC_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.RCI_VAL_MEAN, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
      && NormalizeDouble(st_A_Index.RCI_VAL_SIGMA, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)
   ) {
//printf( "[%d]テスト バッファinsBuffer_st_vAnalyzedIndexに登録しようとする全項目が異常" , __LINE__);
 
      return false;
   }
 
   return true;
}

// バッファinsBuffer_st_vAnalyzedIndex[VTRADENUM_MAX]の中で、
// 引数buf_countのデータを削除（値を初期化）する。
void delete_Buffer_st_vAnalyzedIndex(int buf_count)  {
   if(buf_count >= 0 && buf_count < VTRADENUM_MAX) {
      init_st_vAnalyzedIndexes(insBuffer_st_vAnalyzedIndex[buf_count]);
   }
}

// バッファinsBuffer_st_vAnalyzedIndex[VTRADENUM_MAX]を初期化する。
// ＝　配列内の全件を初期化する。
//     配列内i番目のみを初期化する時は、delete_Buffer_st_vAnalyzedIndex(int buf_count)を使う
void init_insBuffer_st_vAnalyzedIndex() {
   int i = 0;
   for(i = 0; i < VTRADENUM_MAX; i++) {
      init_st_vAnalyzedIndexes(insBuffer_st_vAnalyzedIndex[i]);
   }
}


// バッファinsBuffer_st_vAnalyzedIndex[VTRADENUM_MAX]の中で、
// キー項目に意味のある値が入っている要素の件数を返す。
// stageID,    // ステージ番号。負の時は、ステージ番号を削除条件に加えない。
// strategyID, // 戦略名。　　　長さ0の時は、戦略名を削除条件に加えない。
// symbol,     // 仮想取引の通貨ペア。長さ0の時は、戦略名を削除条件に加えない。
// timeframe,  // 指標計算時の時間軸。15分足のデータを使って指標を計算していれば、PERIOD_M15。負の時は、削除条件に加えない。
// orderType,  // 売買区分。　　OP_BUY及びOP_SELL以外の時は、削除条件に加えない。
// PLFlag,     // 損益区分。vPROFIT, vLOSS以外の時は、削除条件に加えない。
// analyzeTime // 平均、偏差計算時の基準時間。負の時は、削除条件に加えない。
int get_st_vAnalyzedIndexNum(st_vAnalyzedIndex &currStruct[]) {
   int i;
   int retNum = 0;
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(currStruct[i].stageID >= 0
         && StringLen(currStruct[i].strategyID) > 0
         && StringLen(currStruct[i].symbol) > 0
         && currStruct[i].timeframe >= 0
         && (currStruct[i].orderType == OP_BUY || currStruct[i].orderType == OP_SELL) 
         && (currStruct[i].PLFlag == vPROFIT || currStruct[i].PLFlag == vLOSS) ){
         retNum++;
      }
   }
//printf( "[%d]テスト 登録中の4種平均、偏差は%d件" , __LINE__, retNum);
   return retNum;
}

// 4指標が、vAnalyzedIndexテーブルに存在するか検索する。
// 存在すればtrue。存在しなければfalseを返す。
// ピンポイントで、該当するステージ番号のst_BS_PLのデータが登録されていれば、true。
// それ以外は、falseを返す。
bool DB_exist_vAnalyzedIndexes(st_vAnalyzedIndex &st_BS_PL) {
   string Query = "";
   Query = "select * from vAnalyzedIndex where ";
   Query = Query + " stageID  = " + IntegerToString(st_BS_PL.stageID) + " AND ";
   Query = Query + " strategyID  = \'" + st_BS_PL.strategyID + "\' AND ";
   Query = Query + " symbol      = \'" + st_BS_PL.symbol + "\' AND ";
   Query = Query + " timeframe   = " + IntegerToString(st_BS_PL.timeframe) + " AND ";
   Query = Query + " orderType   = " + IntegerToString(st_BS_PL.orderType) + " AND ";
   Query = Query + " PLFlag      = " + IntegerToString(st_BS_PL.PLFlag) + " AND ";
   Query = Query + " analyzeTime = " + IntegerToString(st_BS_PL.analyzeTime)   + ";";

   
   bool retFlag = false;
      
   int intCursor = MySqlCursorOpen(DB, Query);
   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);  
      retFlag = false;            
   }
   else {
      int Rows = MySqlCursorRows(intCursor);
      if(Rows <= 0) {
         retFlag = false;
      }
      else {
         retFlag = true;
      }
   }
   MySqlCursorClose(intCursor);
   
   return retFlag;
}



//+----------------------------------------------------------------------+
//| 指標値と過去の平均、偏差を使って、売買可能かどうかを判断する。       |
//| DB版。引数の個数や、処理ロジックが大幅変更されている。               |
//+---------------------------------------------------------------------+
// 売買判断を行う。
// 売買判断がすべて計算に失敗した場合はfalseを返す。
// 売買判断の結果は、引数blBUY_able, blSELL_ableで返す。
// 【前提】
//  st_vAnalyzedIndex構造体のst_vAnalyzedIndexesBUY_Profit, st_vAnalyzedIndexesBUY_Loss, 
//  st_vAnalyzedIndexesSELL_Profit, st_vAnalyzedIndexesSELL_Lossは、関数実行前に計算済みであること。
// 引数flagBuySell(OP_BUY, OP_SELL)の売買が可能かどうかを、引数judgeMethodの基準で、
// 引数curr_st_vOrderIndexで渡した判断時点指標と、グローバル変数に格納済みの過去指標を使って
// 判断する。
bool DB_judgeTradable(
                   int mStageID,
                   string mStrategyID,
                   st_vOrderIndex &curr_st_vOrderIndex,  // 入力：判断時点の指標を格納した構造体。
                   bool &blBUY_able,                   // 出力：買いが可能な場合に、true
                   bool &blSELL_able                   // 出力：売りが可能な場合に、true
) {
   // 出力用変数をfalseで初期化する。
   blBUY_able  = false;
   blSELL_able = false;
   bool ret = false;  // 関数の返り値。処理が成功した場合にtrueに修正する。関数末尾まで、falseのままなら、全ての処理で不具合発生。
 
   // 引数及びグローバル変数に不具合があれば、falseを返す。
   if(VT_JUDGEMETHOD < 1 && VT_JUDGEMETHOD > 3)  {
      return false;
   }

   if(StringLen(curr_st_vOrderIndex.symbol) <= 0
      || curr_st_vOrderIndex.timeframe < 0
      || curr_st_vOrderIndex.calcTime  <= 0) {
      return false;
   }

   if(VT_POSITIVE_SIGMA < 0.0)  {
      return false;
   }
   if(VT_NEGATIVE_SIGMA < 0.0)  {
      return false;
   }

   bool tradableFlag = false;
   
   // 売買判断時点の指標curr_st_vOrderIndexと比較する平均、偏差4種を読み込む
   bool flg_get_st_vAnalyzedIndex =  DB_get_st_vAnalyzedIndex(mStageID - 1,   // １つ前のステージ番号で、4種の平均、偏差を取得する。
                                                           mStrategyID,
                                                           curr_st_vOrderIndex.symbol,
                                                           curr_st_vOrderIndex.timeframe, 
                                                           curr_st_vOrderIndex.calcTime
                                                           ); 
   if(flg_get_st_vAnalyzedIndex == false) {
      // 4種の平均、偏差の全てを読み込み失敗
printf("[%d]VT 該当する4種st_vAnalyzedIndexesが存在しない", __LINE__);
      
      return false;
   }
   // 
   // 買い取引の判断
   //
   // 判断パターン番号1：全ての項目が買い＆利益の範囲内の時、blBUY_able = true。
   if(VT_JUDGEMETHOD == 1)  {
      if(st_vAnalyzedIndexesBUY_Profit.analyzeTime <= 0) {
         printf("[%d]VT st_vAnalyzedIndexesBUY_Profit.strategyIDが未計算（空欄）のため、買い判断不能", __LINE__);
      }
      else {
         tradableFlag = isInsideOf(st_vAnalyzedIndexesBUY_Profit, VT_POSITIVE_SIGMA, curr_st_vOrderIndex);
         ret = true; // この関数の返り値。売買フラグがtrueになるかは別として、少なくとも、このケースで処理が完了したので、trueにする。
         if(tradableFlag == true)  {
            blBUY_able = true;
         }
      }
   }

   // 判断パターン番号2：全ての項目が買い＆損失の範囲外
   // st_vAnalyzedIndexesBUY_Lossが計算済みであること。
   if(VT_JUDGEMETHOD == 2)  {
      if(st_vAnalyzedIndexesBUY_Loss.analyzeTime <= 0)  {
         printf("[%d]VT st_vAnalyzedIndexesBUY_Los.strategyIDが未計算（空欄）のため、買い判断不能", __LINE__);
      }
      else {
         tradableFlag = isOutsideOf(st_vAnalyzedIndexesBUY_Loss, VT_NEGATIVE_SIGMA, curr_st_vOrderIndex);  
         ret = true; // この関数の返り値。売買フラグがtrueになるかは別として、少なくとも、このケースで処理が完了したので、trueにする。
         if(tradableFlag == true)  {
            blBUY_able = true;
         }
      }
   }

   // 判断パターン番号3：1,2の両立。買い＆利益の範囲内であって、買い＆損失の範囲外。
   // st_vAnalyzedIndexesBUY_Profitが計算済みであること。
   // かつ、st_vAnalyzedIndexesBUY_Lossが計算済みであること。
   if(VT_JUDGEMETHOD == 3) {
      if(st_vAnalyzedIndexesBUY_Profit.analyzeTime <= 0
         || st_vAnalyzedIndexesBUY_Loss.analyzeTime <= 0)  {
         printf("[%d]VT st_vAnalyzedIndexesBUY_Lossまたはst_vAnalyzedIndexesBUY_Lossが未計算（空欄）のため、買い判断不能", __LINE__);
      }
      else {
         tradableFlag = isInsideOf(st_vAnalyzedIndexesBUY_Profit, VT_POSITIVE_SIGMA, curr_st_vOrderIndex);
         ret = true; // この関数の返り値。売買フラグがtrueになるかは別として、少なくとも、このケースで処理が完了したので、trueにする。
         if(tradableFlag == true)  {
            tradableFlag = isOutsideOf(st_vAnalyzedIndexesBUY_Loss, VT_NEGATIVE_SIGMA, curr_st_vOrderIndex);
            if(tradableFlag == true)  {
            blBUY_able = true;
            }
         }
      }
   }      // if(judgeMethod == 3) {


   //
   // 売り取引の判断
   //
   // 判断パターン番号1：全ての項目が買い＆利益の範囲内の時、trueを返す。
   // st_vAnalyzedIndexesSELL_Profitが計算済みであること。
   if(VT_JUDGEMETHOD == 1)  {
      if(st_vAnalyzedIndexesSELL_Profit.analyzeTime <= 0)  {
         printf("[%d]VT st_vAnalyzedIndexesSELL_Profit.strategyIDが未計算（空欄）のため、売り判断不能", __LINE__);
      }
      else {
         tradableFlag = isInsideOf(st_vAnalyzedIndexesSELL_Profit, VT_POSITIVE_SIGMA, curr_st_vOrderIndex);
         ret = true; // この関数の返り値。売買フラグがtrueになるかは別として、少なくとも、このケースで処理が完了したので、trueにする。
         if(tradableFlag == true)  {
            blSELL_able = true;
         }
      }
   }
   // 判断パターン番号2：全ての項目が買い＆損失の範囲外
   // st_vAnalyzedIndexesSELL_Lossが計算済みであること。
   if(VT_JUDGEMETHOD == 2)  {
      if(st_vAnalyzedIndexesSELL_Loss.analyzeTime <= 0)  {
         printf("[%d]VT st_vAnalyzedIndexesSELL_Loss.strategyIDが未計算（空欄）のため、売り判断不能", __LINE__);
      }
      else {
         tradableFlag = isOutsideOf(st_vAnalyzedIndexesSELL_Loss, VT_NEGATIVE_SIGMA, curr_st_vOrderIndex);
         ret = true; // この関数の返り値。売買フラグがtrueになるかは別として、少なくとも、このケースで処理が完了したので、trueにする。
         if(tradableFlag == true)  {
            blSELL_able = true;
         }
      }
   }

   // 判断パターン番号3：1,2の両立。買い＆利益の範囲内であって、買い＆損失の範囲外。
   // st_vAnalyzedIndexesSELL_Profitが計算済みであること。
   // かつ、st_vAnalyzedIndexesSELL_Lossが計算済みであること。
   if(VT_JUDGEMETHOD == 3) {
      if(st_vAnalyzedIndexesSELL_Profit.analyzeTime <= 0
         || st_vAnalyzedIndexesSELL_Loss.analyzeTime <= 0)  {
         printf("[%d]VT st_vAnalyzedIndexesSELL_Lossまたはst_vAnalyzedIndexesSELL_Lossが未計算（空欄）のため、売り判断不能", __LINE__);
      }
      else {
         tradableFlag = isInsideOf(st_vAnalyzedIndexesSELL_Profit, VT_POSITIVE_SIGMA, curr_st_vOrderIndex);
         ret = true; // この関数の返り値。売買フラグがtrueになるかは別として、少なくとも、このケースで処理が完了したので、trueにする。
         if(tradableFlag == true)  {
            tradableFlag = isOutsideOf(st_vAnalyzedIndexesSELL_Loss, VT_NEGATIVE_SIGMA, curr_st_vOrderIndex);
            if(tradableFlag == true)  {
            blSELL_able = true;
            }
         }
      }      
   }         // if(VT_JUDGEMETHOD == 3) {
   return ret;
}


// 引数で渡した通貨ペア、時間軸、計算基準時間を持つvAnalyzedIndexテーブルを読み込み、
// st_vAnalyzedIndexesBUY_Profitの他全4つのグローバル変数に読み込む。
// 検索条件は、mStageID, mSymbolとmTimeframeは一致すること。analyzeTime <= mTargetTimeを満たすこと。
// 上記条件を満たすうち、analyzeTimeが最大であること＝analyzeTimeの降順で取得して、最初の1件を読み込むことで、対応する。
// 4つ全てのグローバル変数への設定に失敗した場合に、falseを返す。
bool DB_get_st_vAnalyzedIndex(int      mStageID,    // 4種の平均、偏差を取得する対象ステージ番号 
                           string   mStrategyID, // 4種の平均、偏差を取得する戦略名
                           string   mSymbol,     // 4種の平均、偏差を取得する対象通貨ペア
                           int      mTimeframe_calc,  // 4種の平均、偏差を取得する時の時間軸
                           datetime mTargetTime  // 4種の平均、偏差を取得する時の計算基準時間
                           ) {
   // st_vAnalyzedIndexesBUY_Profitの取得
   string Query = "";
   Query = "select * from vAnalyzedIndex where ";
   Query = Query + " stageID  = " + IntegerToString(mStageID) + " AND ";   
   Query = Query + " strategyID  = \'" + mStrategyID + "\' AND ";
   Query = Query + " symbol      = \'" + mSymbol + "\' AND ";
   Query = Query + " timeframe   = " + IntegerToString(mTimeframe_calc) + " AND ";
   Query = Query + " orderType   = " + IntegerToString(OP_BUY) + " AND ";
   Query = Query + " PLFlag      = " + IntegerToString(vPROFIT) + " AND ";
   Query = Query + " analyzeTime <= " + IntegerToString(mTargetTime)   + " ";
   Query = Query + " order by analyzeTime DESC;";   

   bool retFlag = false;  // 全滅の時、falseのまま。　→　1つでも取得に成功した時にtrueに変更する。
//printf( "[%d]テスト　ステージ>%d<の仮想取引用にステージ>%d<のst_vAnalyzedIndexesBUY_Profitを取得:%s" , __LINE__, mStageID+1, mStageID, Query);

   int intCursor = MySqlCursorOpen(DB, Query);
   int Rows = 0;
   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);  
      retFlag = false;            
   }
   else {
      Rows = MySqlCursorRows(intCursor);
      if(Rows <= 0) {
//printf( "[%d]テスト　st_vAnalyzedIndexesBUY_Profitの登録無し:%s" , __LINE__, Query);
      
      }
      else {
         retFlag = true; // 少なくとも1件成功したため、関数の返り値はtrue
         MySqlCursorFetchRow(intCursor);    
/*
printf( "[%d]テスト　st_vAnalyzedIndexesBUY_Profitを取得成功:stageID=%d -- %d" , __LINE__, mStageID, MySqlGetFieldAsInt(intCursor, 0));
printf( "[%d]テスト　st_vAnalyzedIndexesBUY_Profitを取得成功:strategyID=%s  -- %s" , __LINE__, mStrategyID,MySqlGetFieldAsInt(intCursor, 1));

printf( "[%d]テスト　st_vAnalyzedIndexesBUY_Profitを取得成功:symbol=%s -- %s" , __LINE__, mSymbol, MySqlGetFieldAsString(intCursor, 2));
printf( "[%d]テスト　st_vAnalyzedIndexesBUY_Profitを取得成功:timeframe=%d -- %d" , __LINE__, mTimeframe, MySqlGetFieldAsInt(intCursor, 3));
printf( "[%d]テスト　st_vAnalyzedIndexesBUY_Profitを取得成功:orderType=%d-- %d" , __LINE__, OP_BUY, MySqlGetFieldAsInt(intCursor, 4));
printf( "[%d]テスト　st_vAnalyzedIndexesBUY_Profitを取得成功:PLFlag=%d -- %d" , __LINE__, vPROFIT, MySqlGetFieldAsInt(intCursor, 5));
printf( "[%d]テスト　st_vAnalyzedIndexesBUY_Profitを取得成功:analyzeTime=%d -- %d" , __LINE__, mTargetTime, MySqlGetFieldAsInt(intCursor, 6));
*/
         st_vAnalyzedIndexesBUY_Profit.stageID = mStageID;       // MySqlGetFieldAsInt(intCursor, 0);
         st_vAnalyzedIndexesBUY_Profit.strategyID = mStrategyID; // MySqlGetFieldAsString(intCursor, 1);
         st_vAnalyzedIndexesBUY_Profit.symbol = mSymbol;         // MySqlGetFieldAsString(intCursor, 2);
         st_vAnalyzedIndexesBUY_Profit.timeframe = mTimeframe_calc;   // MySqlGetFieldAsInt(intCursor, 3);
         st_vAnalyzedIndexesBUY_Profit.orderType = OP_BUY;       // MySqlGetFieldAsInt(intCursor, 4);
         st_vAnalyzedIndexesBUY_Profit.PLFlag    = vPROFIT;      // MySqlGetFieldAsInt(intCursor, 5);
         st_vAnalyzedIndexesBUY_Profit.analyzeTime = mTargetTime;// MySqlGetFieldAsInt(intCursor, 6);
                                                                 // MySqlGetFieldAsInt(intCursor, 7);

         st_vAnalyzedIndexesBUY_Profit.MA_GC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 8), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_GC_SIGMA      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 9), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_DC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 10), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_DC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 11), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_Slope5_MEAN   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 12), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_Slope5_SIGMA  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 13), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_Slope25_MEAN  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 14), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_Slope25_SIGMA = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 15), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_Slope75_MEAN  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 16), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_Slope75_SIGMA = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 17), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.BB_Width_MEAN    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 18), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.BB_Width_SIGMA   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 19), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.IK_TEN_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 20), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.IK_TEN_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 21), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.IK_CHI_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 22), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.IK_CHI_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 23), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.IK_LEG_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 24), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.IK_LEG_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 25), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MACD_GC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 26), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MACD_GC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 27), global_Digits);                  
         st_vAnalyzedIndexesBUY_Profit.MACD_DC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 28), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MACD_DC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 29), global_Digits);                  
         st_vAnalyzedIndexesBUY_Profit.RSI_VAL_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 30), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.RSI_VAL_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 31), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.STOC_VAL_MEAN    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 32), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.STOC_VAL_SIGMA   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 33), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.STOC_GC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 34), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.STOC_GC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 35), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.STOC_DC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 36), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.STOC_DC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 37), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.RCI_VAL_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 38), global_Digits);
         st_vAnalyzedIndexesBUY_Profit.RCI_VAL_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 39), global_Digits);
       
      }
   }
   MySqlCursorClose(intCursor);

   //
   // st_vAnalyzedIndexesBUY_Lossの取得
   Query = "";
   Query = "select * from vAnalyzedIndex where ";
   Query = Query + " stageID  = " + IntegerToString(mStageID) + " AND ";   
   Query = Query + " strategyID  = \'" + mStrategyID + "\' AND ";
   Query = Query + " symbol      = \'" + mSymbol + "\' AND ";
   Query = Query + " timeframe   = " + IntegerToString(mTimeframe_calc) + " AND ";
   Query = Query + " orderType   = " + IntegerToString(OP_BUY) + " AND ";
   Query = Query + " PLFlag      = " + IntegerToString(vLOSS) + " AND ";
   Query = Query + " analyzeTime <= " + IntegerToString(mTargetTime)   + " ";
   Query = Query + " order by analyzeTime DESC;";   

   retFlag = false;
//printf( "[%d]テスト　ステージ>%d<の仮想取引用にステージ>%d<のst_vAnalyzedIndexesBUY_Lossを取得:%s" , __LINE__, mStageID+1, mStageID, Query);
   intCursor = MySqlCursorOpen(DB, Query);
   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);  
   }
   else {
      Rows = MySqlCursorRows(intCursor);
      if(Rows <= 0) {
//printf( "[%d]テスト　st_vAnalyzedIndexesBUY_Lossを取得失敗0件:%s" , __LINE__, Query);
      }
      else {
         retFlag = true; // 少なくとも1件成功したため、関数の返り値はtrue      
         MySqlCursorFetchRow(intCursor);    

//printf( "[%d]テスト　st_vAnalyzedIndexesBUY_Lossを取得成功:%s" , __LINE__, Query);
         st_vAnalyzedIndexesBUY_Loss.stageID = mStageID;       // MySqlGetFieldAsInt(intCursor, 0);
         st_vAnalyzedIndexesBUY_Loss.strategyID = mStrategyID; // MySqlGetFieldAsString(intCursor, 1);
         st_vAnalyzedIndexesBUY_Loss.symbol = mSymbol;         // MySqlGetFieldAsString(intCursor, 2);
         st_vAnalyzedIndexesBUY_Loss.timeframe = mTimeframe_calc;   // MySqlGetFieldAsInt(intCursor, 3);
         st_vAnalyzedIndexesBUY_Loss.orderType = OP_BUY;       // MySqlGetFieldAsInt(intCursor, 4);
         st_vAnalyzedIndexesBUY_Loss.PLFlag    = vPROFIT;      // MySqlGetFieldAsInt(intCursor, 5);
         st_vAnalyzedIndexesBUY_Loss.analyzeTime = mTargetTime;// MySqlGetFieldAsInt(intCursor, 6);
                                                                 // MySqlGetFieldAsInt(intCursor, 7);
         st_vAnalyzedIndexesBUY_Loss.MA_GC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 8), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_GC_SIGMA      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 9), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_DC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 10), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_DC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 11), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_Slope5_MEAN   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 12), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_Slope5_SIGMA  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 13), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_Slope25_MEAN  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 14), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_Slope25_SIGMA = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 15), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_Slope75_MEAN  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 16), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_Slope75_SIGMA = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 17), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.BB_Width_MEAN    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 18), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.BB_Width_SIGMA   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 19), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.IK_TEN_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 20), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.IK_TEN_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 21), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.IK_CHI_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 22), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.IK_CHI_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 23), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.IK_LEG_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 24), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.IK_LEG_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 25), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MACD_GC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 26), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MACD_GC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 27), global_Digits);                  
         st_vAnalyzedIndexesBUY_Loss.MACD_DC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 28), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MACD_DC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 29), global_Digits);                  
         st_vAnalyzedIndexesBUY_Loss.RSI_VAL_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 30), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.RSI_VAL_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 31), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.STOC_VAL_MEAN    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 32), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.STOC_VAL_SIGMA   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 33), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.STOC_GC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 34), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.STOC_GC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 35), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.STOC_DC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 36), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.STOC_DC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 37), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.RCI_VAL_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 38), global_Digits);
         st_vAnalyzedIndexesBUY_Loss.RCI_VAL_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 39), global_Digits);
      }
   }
   MySqlCursorClose(intCursor);

   //
   // st_vAnalyzedIndexesSELL_Profitの取得
   Query = "";
   Query = "select * from vAnalyzedIndex where ";
   Query = Query + " stageID  = " + IntegerToString(mStageID) + " AND ";
   Query = Query + " strategyID  = \'" + mStrategyID + "\' AND ";
   Query = Query + " symbol      = \'" + mSymbol + "\' AND ";
   Query = Query + " timeframe   = " + IntegerToString(mTimeframe_calc) + " AND ";
   Query = Query + " orderType   = " + IntegerToString(OP_SELL) + " AND ";
   Query = Query + " PLFlag      = " + IntegerToString(vPROFIT) + " AND ";
   Query = Query + " analyzeTime <= " + IntegerToString(mTargetTime)   + " ";
   Query = Query + " order by analyzeTime DESC;";   

   retFlag = false;
//printf( "[%d]テスト　ステージ>%d<の仮想取引用にステージ>%d<のst_vAnalyzedIndexesSELL_Profitを取得:%s" , __LINE__, mStageID+1, mStageID, Query);
   intCursor = MySqlCursorOpen(DB, Query);
   Rows = 0;
   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);  
   }
   else {
      Rows = MySqlCursorRows(intCursor);
      if(Rows <= 0) {
//printf( "[%d]テスト　st_vAnalyzedIndexesSELL_Profitを取得失敗0件:%s" , __LINE__, Query);
      
      }
      else {
         retFlag = true; // 少なくとも1件成功したため、関数の返り値はtrue      
         MySqlCursorFetchRow(intCursor);    
//printf( "[%d]テスト　st_vAnalyzedIndexesSELL_Profitを取得成功:%s" , __LINE__, Query);
         st_vAnalyzedIndexesSELL_Profit.stageID = mStageID;       // MySqlGetFieldAsInt(intCursor, 0);
         st_vAnalyzedIndexesSELL_Profit.strategyID = mStrategyID; // MySqlGetFieldAsString(intCursor, 1);
         st_vAnalyzedIndexesSELL_Profit.symbol = mSymbol;         // MySqlGetFieldAsString(intCursor, 2);
         st_vAnalyzedIndexesSELL_Profit.timeframe = mTimeframe_calc;   // MySqlGetFieldAsInt(intCursor, 3);
         st_vAnalyzedIndexesSELL_Profit.orderType = OP_BUY;       // MySqlGetFieldAsInt(intCursor, 4);
         st_vAnalyzedIndexesSELL_Profit.PLFlag    = vPROFIT;      // MySqlGetFieldAsInt(intCursor, 5);
         st_vAnalyzedIndexesSELL_Profit.analyzeTime = mTargetTime;// MySqlGetFieldAsInt(intCursor, 6);
                                                                 // MySqlGetFieldAsInt(intCursor, 7);
         st_vAnalyzedIndexesSELL_Profit.MA_GC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 8), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_GC_SIGMA      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 9), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_DC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 10), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_DC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 11), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_Slope5_MEAN   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 12), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_Slope5_SIGMA  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 13), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_Slope25_MEAN  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 14), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_Slope25_SIGMA = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 15), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_Slope75_MEAN  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 16), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_Slope75_SIGMA = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 17), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.BB_Width_MEAN    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 18), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.BB_Width_SIGMA   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 19), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.IK_TEN_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 20), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.IK_TEN_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 21), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.IK_CHI_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 22), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.IK_CHI_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 23), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.IK_LEG_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 24), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.IK_LEG_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 25), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MACD_GC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 26), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MACD_GC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 27), global_Digits);                  
         st_vAnalyzedIndexesSELL_Profit.MACD_DC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 28), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MACD_DC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 29), global_Digits);                  
         st_vAnalyzedIndexesSELL_Profit.RSI_VAL_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 30), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.RSI_VAL_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 31), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.STOC_VAL_MEAN    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 32), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.STOC_VAL_SIGMA   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 33), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.STOC_GC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 34), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.STOC_GC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 35), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.STOC_DC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 36), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.STOC_DC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 37), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.RCI_VAL_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 38), global_Digits);
         st_vAnalyzedIndexesSELL_Profit.RCI_VAL_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 39), global_Digits);
      }
   }
   MySqlCursorClose(intCursor);


   //
   // st_vAnalyzedIndexesSELL_Lossの取得
   Query = "";
   Query = "select * from vAnalyzedIndex where ";
   Query = Query + " stageID  = " + IntegerToString(mStageID) + " AND ";
   Query = Query + " strategyID  = \'" + mStrategyID + "\' AND ";
   Query = Query + " symbol      = \'" + mSymbol + "\' AND ";
   Query = Query + " timeframe   = " + IntegerToString(mTimeframe_calc) + " AND ";
   Query = Query + " orderType   = " + IntegerToString(OP_SELL) + " AND ";
   Query = Query + " PLFlag      = " + IntegerToString(vLOSS) + " AND ";
   Query = Query + " analyzeTime <= " + IntegerToString(mTargetTime)   + " ";
   Query = Query + " order by analyzeTime DESC;";   

   retFlag = false;
//printf( "[%d]テスト　ステージ>%d<の仮想取引用にステージ>%d<のst_vAnalyzedIndexesSELL_Lossを取得:%s" , __LINE__, mStageID+1, mStageID, Query);
   intCursor = MySqlCursorOpen(DB, Query);
   Rows = 0;   
   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);  
   }
   else {
      Rows = MySqlCursorRows(intCursor);
      if(Rows <= 0) {
//printf( "[%d]テスト　st_vAnalyzedIndexesSELL_Lossを取得失敗0件:%s" , __LINE__, Query);
      
      }
      else {
         retFlag = true; // 少なくとも1件成功したため、関数の返り値はtrue      
         MySqlCursorFetchRow(intCursor);    
//printf( "[%d]テスト　st_vAnalyzedIndexesSELL_Lossを取得成功:%s" , __LINE__, Query);
         st_vAnalyzedIndexesSELL_Loss.stageID = mStageID;       // MySqlGetFieldAsInt(intCursor, 0);
         st_vAnalyzedIndexesSELL_Loss.strategyID = mStrategyID; // MySqlGetFieldAsString(intCursor, 1);
         st_vAnalyzedIndexesSELL_Loss.symbol = mSymbol;         // MySqlGetFieldAsString(intCursor, 2);
         st_vAnalyzedIndexesSELL_Loss.timeframe = mTimeframe_calc;   // MySqlGetFieldAsInt(intCursor, 3);
         st_vAnalyzedIndexesSELL_Loss.orderType = OP_BUY;       // MySqlGetFieldAsInt(intCursor, 4);
         st_vAnalyzedIndexesSELL_Loss.PLFlag    = vPROFIT;      // MySqlGetFieldAsInt(intCursor, 5);
         st_vAnalyzedIndexesSELL_Loss.analyzeTime = mTargetTime;// MySqlGetFieldAsInt(intCursor, 6);
                                                                 // MySqlGetFieldAsInt(intCursor, 7);
         st_vAnalyzedIndexesSELL_Loss.MA_GC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 8), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_GC_SIGMA      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 9), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_DC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 10), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_DC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 11), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_Slope5_MEAN   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 12), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_Slope5_SIGMA  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 13), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_Slope25_MEAN  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 14), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_Slope25_SIGMA = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 15), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_Slope75_MEAN  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 16), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_Slope75_SIGMA = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 17), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.BB_Width_MEAN    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 18), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.BB_Width_SIGMA   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 19), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.IK_TEN_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 20), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.IK_TEN_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 21), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.IK_CHI_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 22), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.IK_CHI_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 23), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.IK_LEG_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 24), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.IK_LEG_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 25), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MACD_GC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 26), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MACD_GC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 27), global_Digits);                  
         st_vAnalyzedIndexesSELL_Loss.MACD_DC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 28), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MACD_DC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 29), global_Digits);                  
         st_vAnalyzedIndexesSELL_Loss.RSI_VAL_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 30), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.RSI_VAL_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 31), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.STOC_VAL_MEAN    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 32), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.STOC_VAL_SIGMA   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 33), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.STOC_GC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 34), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.STOC_GC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 35), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.STOC_DC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 36), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.STOC_DC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 37), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.RCI_VAL_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 38), global_Digits);
         st_vAnalyzedIndexesSELL_Loss.RCI_VAL_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 39), global_Digits);
      }
   }
   MySqlCursorClose(intCursor);

   return true;
}                                                           
                                                           

// 引数で指定したステージの取引数を返す。
int DB_get_vOrdersNum_stage(int    mStageID,     // ステージ番号
                         string mStrategyID,  // 戦略名 
                         string mSymbol,  // 通貨ペア
                         int    mTimeFrame) {
   string strBuf = "select count(*) from vtradetable";
   strBuf = strBuf + " where ";
   strBuf = strBuf + " stageID = " + IntegerToString(mStageID) ;   
   strBuf = strBuf + " AND ";
   strBuf = strBuf + " strategyID = \'" + mStrategyID + "\'";
   strBuf = strBuf + " AND ";
   strBuf = strBuf + " symbol = \'" + mSymbol + "\'";   
   strBuf = strBuf + " AND ";
   strBuf = strBuf + " timeframe = " + IntegerToString(mTimeFrame) ;   
   
   int intCursor = MySqlCursorOpen(DB, strBuf);
   int retNum = 0;
   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, strBuf);  
      retNum = 0;            
   }
   else {
//printf( "[%d]テスト　　　ステージ%dのvtradeを検索する:%s" , __LINE__, mStageID, strBuf);  
   
      int Rows = MySqlCursorRows(intCursor);
      if(Rows > 0) {
         if (MySqlCursorFetchRow(intCursor)) {
            retNum = MySqlGetFieldAsInt(intCursor, 0);
         }
      }
   }
   MySqlCursorClose(intCursor);

//printf( "[%d]テスト　ステージ=%dのデータ件数%d 　:%s:%s:%d" , __LINE__, mStageID, retNum, mStrategyID, mSymbol, mTimeFrame);

   return retNum;
}                                              
                                           


// puelladb.pricetableを引数の通貨ペアと時間軸をキーとして検索し、
// テーブル上の最新データ以降で、引数の更新基準時間までのデータが無ければ、追加する。
// 追加に成功した時、又は、追加が不要だった時はtrue
// 追加処理が失敗した時は、false
bool DB_add_PriceFromHistoryCentor(string   mSymbol,     // 通貨ペア名。Symbol()の値。
                                   int      mTimeframe,  //　PERIOD_M1。price, index, 新規発注を行う間隔
                                   datetime mTargetDt,   // 更新基準時間
                                   int      mEND_SHIFT   // 処理対象となる最古のシフト番号が設定されていない場合に、このシフト番号まで処理を行う。
                                  ) {
   datetime startDt = -1;
   datetime endDt   = mTargetDt;
   int      max_price_dt = -1;

   // 引数mSymbolとmTimeframeを使ってpricetableを検索し、最大のdt(=発生時刻)を取得する。
   string Query = "";
   Query = Query + "select max(dt) from pricetable ";
   Query = Query + " where symbol = \'" + mSymbol + "\'";
   Query = Query + " and timeframe = "  + IntegerToString(mTimeframe) + " ";
   int intCursor = MySqlCursorOpen(DB, Query);

   //カーソルの取得失敗時は後続処理をしない。
   if(intCursor < 0) {
      printf( "[%d]エラー　カーソルオープン失敗:%s:%s" , __LINE__, MySqlErrorDescription, Query);
      startDt = -1;      
   }
   else {
      int Rows = MySqlCursorRows(intCursor);
      if(Rows > 0) {
         if (MySqlCursorFetchRow(intCursor)) {
            // カーソルの指す1件を取得する。
            max_price_dt = MySqlGetFieldAsInt(intCursor, 0);
         }
      }
   }
   MySqlCursorClose(intCursor);
   // 
   // 以上で、追加開始時刻を用意できた。
   // 

   // 最大のdt(=発生時刻)が取得できなかった時は、先頭から追加。　　→グローバル変数END_SHIFT×mTimeframe前から引数mTargetDtまでを追加する。
   if(max_price_dt < 0) {
      startDt = mTargetDt - mEND_SHIFT * (mTimeframe*60);
   } 
   // 最大のdt(=発生時刻) > mTargetDtの時は、追加不要　　　　　　　→何もしない。
   else if(max_price_dt > mTargetDt) {
/*      printf( "[%d]テスト　pricetableの追加:最新データが%sのため、引数%sのデータは登録済み" ,
               __LINE__, 
               TimeToStr(max_price_dt), 
               TimeToStr(mTargetDt)    );*/

      // 何もしない
      return true;
   }
   // 0 <= 最大のdt(=発生時刻) < mTargetDtの時は、最大のdtから追加。→最大のdt(=発生時刻)から引数mTargetDtまでを追加する。
   else if(max_price_dt >= 0 && max_price_dt <= mTargetDt) {
      startDt = max_price_dt + 1;
   } 

   if(max_price_dt < 0) {
      printf( "[%d]テスト　pricetableの追加:登録済みデータの最新日付(datetime型)が>%d<のため、引数%sのデータは登録できない" ,
               __LINE__, 
               max_price_dt, 
               TimeToStr(mTargetDt)    );

      // 何もしない
      return true;
   }

   bool ret = DB_insert_PriceFromHistoryCentor(mSymbol,    // 通貨ペア名。Symbol()の値。
                                            mTimeframe, //　PERIOD_M1。price, index, 新規発注を行う間隔
                                            startDt,    // インポート開始時刻。
                                            endDt       // インポート終了時刻。
                                           );

   return ret;
}


// puelladb.pricetableのデータを通貨ペアと時間軸をキーとして、全件削除し、
// 引数で指定した通貨ペア、時間軸、タイムフレームをキーとして、シフトSTART_SHIFT～END_SHIFTの、puelladb.pricetableデータをインポートする。
// 第2引数をPERIOD_M1とすることで、1分足データをインポートする。
// ※puelladb.pricetableのデータを追加するには、別関数を用意する。
bool DB_insert_PriceFromHistoryCentor(string mSymbol,   // 通貨ペア名。Symbol()の値。
                                   int mTimeframe,     //　PERIOD_M1。price, index, 新規発注を行う間隔
                                   int mBarShiftStart, // インポート開始時点のシフト。mBarShiftStart < mBarShiftEndであること。
                                   int mBarShiftEnd    // インポート終了時点のシフト。mBarShiftStart < mBarShiftEndであること。
                                  ) {
//   int timeframe = Period();
//   string currPair = "EURUSD-cd";
   bool errFlag = true;
   if(mBarShiftStart > mBarShiftEnd) {
printf( "[%d]エラー　第3引数>第4引数は誤り:%s:時間軸=%d スタート=%d  エンド=%d" , __LINE__, 
           mSymbol,
           mTimeframe,
           mBarShiftStart,
           mBarShiftEnd);
      return false;

   }
/*printf( "[%d]テスト　insert_PriceFromの引数:%s:時間軸=%d スタート=%d  エンド=%d" , __LINE__, 
           mSymbol,
           mTimeframe,
           mBarShiftStart,
           mBarShiftEnd);
  */ 
   string bufOpen = "";
   string bufHigh = "";
   string bufLow = "";
   string bufClose = "";
   string bufVolume = "";

   // pricetableからデータを削除するSQLの基本形
   string Query = "delete from pricetable where " +
                  "symbol = \'" + mSymbol + "\' and " +
                  "timeframe = " + IntegerToString(mTimeframe);
   //
   // pricetableからデータを削除するための絞り込み
   // 引数mBarShiftStart(iOpen)及びmBarShiftEnd(iClose)が0以上ならば、delete文の実行対象を絞り込む。
   string postQuery = "";
   datetime dt_start = -1; // delete文の実行対象の開始時間
   datetime dt_end   = -1; // delete文の実行対象の終了時間
   if(mBarShiftStart < 0 && mBarShiftEnd < 0) {
      // mBarShiftStart及びmBarShiftEndが共に負の場合は、pricetable.dtによる絞り込みはしない。
   }
   else {
      // シフトmBarShiftStart < mBarShiftEndが必須としており、
      // 時間の単位に直した時は、mBarShiftStartの時間 >　mBarShiftEndの時間であることに注意
      if(mBarShiftStart >= 0) {
         dt_end = iTime(mSymbol, mTimeframe, mBarShiftStart);
         if(StringLen(postQuery) > 0) {
            // シフト番号mBarShiftStartが、mBarShiftEndより現在に近い時間
            postQuery = postQuery + " and " + "dt <= " + IntegerToString(dt_end) + " ";
         }
         else {
            postQuery = postQuery +           "dt <= " + IntegerToString(dt_end) + " ";
         }
      }  
      else {
         // 引数mBarShiftStartが負の時は、絞り込み条件にしない。
      }
      if(mBarShiftEnd >= 0) {
         dt_start   = iTime(mSymbol, mTimeframe, mBarShiftEnd);
         if(StringLen(postQuery) > 0) {
            postQuery = postQuery + " and " + "dt >= " + IntegerToString(dt_start) + " ";
         }
         else {
            postQuery = postQuery +           "dt >= " + IntegerToString(dt_start) + " ";
         }
      }
 
   }  // else = mBarShiftStartとmBarShiftEndのどちらかが正。
   
   // postQueryを使った絞り込み追加があれば、Queryに追加する。
   if(StringLen(postQuery) > 0) {
      Query  = Query + " and " + postQuery;
   }


//printf( "[%d]テスト　pricetableからデータを削除:%s" , __LINE__, Query);
                  
   if(errFlag == true) { 
      //SQL文を実行
      if (MySqlExecute(DB, Query) == true) {
     	}
      else {
         printf( "[%d]エラー　削除失敗:%s" , __LINE__, MySqlErrorDescription);              
         printf( "[%d]エラー　追加失敗時のSQL:%s" , __LINE__, Query);
         errFlag = false;   
      }   

      int barShift = 0;
      double buf = 0.0;
      long   longBuf = 0;
      bool blFailGetData = false; // 値の取得に失敗したらtrueにする。

      //
      // この行までの処理で、引数のシフトmBarShiftStartからmBarShiftEndまでのpricetableデータを削除した。
      //


      for(barShift = mBarShiftStart; barShift <= mBarShiftEnd; barShift++) {
         buf = iOpen(mSymbol, mTimeframe, barShift);
         if(buf > 0.0) {
            bufOpen = DoubleToStr(NormalizeDouble(buf, global_Digits), global_Digits);
         }
         else {
            blFailGetData = true;
         }
         
         if(blFailGetData == false) {
            buf = iHigh(mSymbol, mTimeframe, barShift);
            if(buf > 0.0) {
               bufHigh = DoubleToStr(NormalizeDouble(buf, global_Digits), global_Digits);
            }
            else {
               blFailGetData = true;
            } 
         }

         if(blFailGetData == false) {
            buf = iLow(mSymbol, mTimeframe, barShift);
            if(buf > 0.0) {
               bufLow = DoubleToStr(NormalizeDouble(buf, global_Digits), global_Digits);
            }
            else {
               blFailGetData = true;
            } 
         }

         if(blFailGetData == false) {
            buf = iClose(mSymbol, mTimeframe, barShift);
            if(buf > 0.0) {
               bufClose = DoubleToStr(NormalizeDouble(buf, global_Digits), global_Digits);
            }
            else {
               blFailGetData = true;
            } 
         }

         if(blFailGetData == false) {
            longBuf = iVolume(mSymbol, mTimeframe, barShift);
            if(longBuf > 0) {
               bufVolume = DoubleToStr(longBuf, global_Digits);
            }
            else {
               blFailGetData = true;
            } 
         }

         datetime bufDT = iTime(mSymbol, mTimeframe, barShift);
         Query = "INSERT INTO `pricetable` (symbol, timeframe, dt, dt_str, open, high, low, close, volume) VALUES ("+ "\'" +
                mSymbol + "\', " +                 	//通貨ペア
            	IntegerToString(mTimeframe) + ", " +	   //タイムフレーム
            	IntegerToString(bufDT) + ", \'" + //時間。整数値
            	TimeToStr(bufDT) + "\', " +       //時間。文字列
            	bufOpen   + ", " +                //始値
            	bufHigh   + ", " +                //高値
            	bufLow    + ", " +                //安値
            	bufClose  + ", " +                //終値
            	bufVolume +                       //出来高
              ")";
//      printf( "[%d]テスト　insert pricetable シフト=%d 時間=%s" , __LINE__ ,barShift, TimeToStr(bufDT));
              
         //SQL文を実行
       	if (MySqlExecute(DB, Query) == true) {
         }
         else {
            printf( "[%d]エラー　追加失敗:%s" , __LINE__, MySqlErrorDescription);              
            printf( "[%d]エラー　追加失敗時のSQL:%s" , __LINE__, Query);              
            errFlag = false;
         }
         
      }
   }

   if(errFlag == true) {
      return true;
   }
   else {
      return false;
   }
   
   return true;
}



// 関数insert_PriceFromHistoryCentorの引数違い。
// 第3引数、第4引数が、時刻(datetime型データ)に変わった。
// 第3引数、第4引数を含むバーを計算し、関数insert_PriceFromHistoryCentorを呼び出す。
bool DB_insert_PriceFromHistoryCentor(string   mSymbol,    // 通貨ペア名。Symbol()の値。
                                      int      mTimeframe, //　PERIOD_M1。price, index, 新規発注を行う間隔
                                      datetime mStartDt,   // インポート開始時刻。
                                      datetime mEndDt      // インポート終了時刻。
                                  ) {
   // 引数チェック
   if(mStartDt < 0) {// 処理開始時刻が負の場合は、0に読み替える。
      mStartDt = 0;
   }
   if(mEndDt < 0) {  // 処理終了時刻が負の場合は、実行時の時刻を終了時刻に読み替える。
      mEndDt = Time[0];
   }
   if(mStartDt > mEndDt) {
      return false;
   }

   bool errFlag = true;
   // datetime型でmStartDt <= mEndDの時、シフト番号はshiftStart > shiftEndと逆転させる必要あり。
   int shiftStart = iBarShift(mSymbol, mTimeframe, mEndDt); 
   int shiftEnd   = iBarShift(mSymbol, mTimeframe, mStartDt); 

   // 指定した時刻のシフト番号を取得できなければ、処理を中断する。
   if(shiftStart < 0 || shiftEnd < 0) {
      return false;
   }

   errFlag = DB_insert_PriceFromHistoryCentor(mSymbol,    // 通貨ペア名。Symbol()の値。
                                              mTimeframe, //　PERIOD_M1。price, index, 新規発注を行う間隔
                                              shiftStart, // インポート開始時点のシフト
                                              shiftEnd    // インポート終了時点のシフト
                                           );
   if(errFlag == true) {
      return true;
   }
   else {
      return false;
   }
   
   return true;
}




/*

実取引前に、仮想取引で最も成績の良いパラメータを計算する
パラメータを満たしている時だけ、実取引する。
利確pips
損切pips
flooring
実取引間隔　分
仮想取引間隔　分

5分以上ごとに仮想取引実施
約定値は1分足のクローズ値
クローズは毎分のクローズ値





DBに1分データを保存　　pricetable
各分のパラメータを保存    paramtable, completerate=計算成功÷全パラメータ数を保持。
●ここまでは、実取引、仮想取引によらず固定


各分で仮想取引を作成        vtradetable 
                                                  stage=1,  メソッド=一律1, パラメータ適合率=一律0%
    paramtable(completerate=100%)のレコードの時間で、
　vtradetableに買いと売りを追加する。   
     約定値は、pricetableのcloseを使う。
　決済損益、評価損益は、4種分析時に計算する。  
                                                                        
各分で4種平均偏差分析      vbuysell_pltable
                                                  stage=1, メソッド=1のみ、分析対象=上位5%-100%。
　　　　　　　　　　　　根拠件数、completerate=計算成功÷全パラメータ数を保持。
    paramtable(completerate=100%)のレコードの時間で、
    vbuysell_pltableに4種分析を追加する。
    追加する基準時間でvtradetable(stage=1)の決済損益、評価損益を計算し、
    4種の上位5%-100%を対象として平均偏差を計算する。
    つまり、4種&メソッド1のみ&上位5%-100%20から、基準時間当たり最大80レコードできる。
    
●ここから(stage=2以降)は、
　vbuysell_pltable(stage=n以下、completerate=100%)のレコードの時間で、
　仮想取引追加と4種分析をする。
　
stage=n(2以降)                               
各分で4種分析を使った仮想取引を作成
                                                  vtradetable 
                                                  stage=n,  メソッド=1-3,  パラメータ適合率=5%-100%
    vbuysell_pltable(stage<nを満たす最大, completerate=100%)のレコードの時間で、
　vtradetableに買いと売りを追加する。
　買いと売り&メソッド3&適合率20から、時間当たり最大120レコードできる。
                                              

各分で4種平均偏差分析      vbuysell_pltable
                                                  stage=n, 分析対象=上位5%-100%。
　　　　　　　　　　　　根拠件数、completerate=計算成功÷全パラメータ数を保持。
    paramtable(completerate=100%)のレコードの時間で、
    vbuysell_pltableに4種分析を追加する。
    追加する基準時間でvtradetable(stage=n)の決済損益、評価損益を計算し、
    4種の上位5%-100%を対象として平均偏差を計算する。
    つまり、4種&メソッド1-3&上位5%-100%20から、基準時間当たり最大240レコードできる。
    
    */







/*

実取引前に、仮想取引で最も成績の良いパラメータを計算する
パラメータを満たしている時だけ、実取引する。
利確pips
損切pips
flooring
実取引間隔　分
仮想取引間隔　分

5分以上ごとに仮想取引実施
約定値は1分足のクローズ値
クローズは毎分のクローズ値





DBに1分データを保存　　pricetable
各分のパラメータを保存    paramtable, completerate=計算成功÷全パラメータ数を保持。
●ここまでは、実取引、仮想取引によらず固定


各分で仮想取引を作成        vtradetable 
                                                  stage=1,  メソッド=一律1, パラメータ適合率=一律0%
    paramtable(completerate=100%)のレコードの時間で、
　vtradetableに買いと売りを追加する。   
     約定値は、pricetableのcloseを使う。
　決済損益、評価損益は、4種分析時に計算する。  
                                                                        
各分で4種平均偏差分析      vbuysell_pltable
                                                  stage=1, メソッド=1のみ、分析対象=上位5%-100%。
　　　　　　　　　　　　根拠件数、completerate=計算成功÷全パラメータ数を保持。
    paramtable(completerate=100%)のレコードの時間で、
    vbuysell_pltableに4種分析を追加する。
    追加する基準時間でvtradetable(stage=1)の決済損益、評価損益を計算し、
    4種の上位5%-100%を対象として平均偏差を計算する。
    つまり、4種&メソッド1のみ&上位5%-100%20から、基準時間当たり最大80レコードできる。
    
●ここから(stage=2以降)は、
　vbuysell_pltable(stage=n以下、completerate=100%)のレコードの時間で、
　仮想取引追加と4種分析をする。
　
stage=n(2以降)                               
各分で4種分析を使った仮想取引を作成
                                                  vtradetable 
                                                  stage=n,  メソッド=1-3,  パラメータ適合率=5%-100%
    vbuysell_pltable(stage<nを満たす最大, completerate=100%)のレコードの時間で、
　vtradetableに買いと売りを追加する。
　買いと売り&メソッド3&適合率20から、時間当たり最大120レコードできる。
                                              

各分で4種平均偏差分析      vbuysell_pltable
                                                  stage=n, 分析対象=上位5%-100%。
　　　　　　　　　　　　根拠件数、completerate=計算成功÷全パラメータ数を保持。
    paramtable(completerate=100%)のレコードの時間で、
    vbuysell_pltableに4種分析を追加する。
    追加する基準時間でvtradetable(stage=n)の決済損益、評価損益を計算し、
    4種の上位5%-100%を対象として平均偏差を計算する。
    つまり、4種&メソッド1-3&上位5%-100%20から、基準時間当たり最大240レコードできる。
    
 */






