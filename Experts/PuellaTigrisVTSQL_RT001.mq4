// 20220315動作確認　→　printf( "[%d]テスト past_max=%s と　past_min=%sをENTRY_WIDTH_PIPS=%sで分割し、%d個の候補を作る" , __LINE__ , 


//20220314 001　新規作成。 PuellaTigrisVTSQLで作成した平均、偏差vAnalyzedIndexを用いた実取引RT(RealTrade)発注EA。
//              基本方針は、PuellaTigrisEIで用いている高価格帯で売り、低価格帯で買いを行う際に、平均、偏差vAnalyzedIndexを満たしていることを追加する。

// 【注意】
// 評価損益を計算する際、(評価基準日close - 約定値)　/ global_Digits を計算すると、(1.1391 - 1.1391) / 0.00001が0にならなかった
// →　テーブル無いの各値が小数点5桁でも同様の問題が発生する。
// →　テーブルのデータ型FLOATにしていたために発生した誤差
//   https://qiita.com/rita_cano_bika/items/9649cceec66da5d39389
//   https://dev.mysql.com/doc/refman/5.6/ja/precision-math-decimal-characteristics.html
// →　DECIMAL型にすることで解決した

//+------------------------------------------------------------------+	
//| PuellaTigrisVTSQL_RT(Real Trade)                                 |	
//|  Copyright (c) 2016 トラの親 All rights reserved.                |	
//|                                                                  |
//+------------------------------------------------------------------+	
#property copyright "Copyright (c) 2016 トラの親 All rights reserved."				
#property link      "http://nenshuuha.blog.fc2.com/"			
#property version   "1.00"
#property strict
//+------------------------------------------------------------------+	
//| ヘッダーファイル読込                                                     |	
//+------------------------------------------------------------------+	
#include <stderror.mqh>	
#include <stdlib.mqh>	
#include <Tigris_VirtualTrade.mqh>
//#include <Puer_STAT.mqh>
#include <MQLMySQL.mqh>

//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	
#define DB_VTRADENUM_MAX 10000


//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
extern string EvenIntParameters = "99.---EIのパラメータ---";
extern int MagicNumberVTSQLRT  = 20220314;
extern int PAST_SPAN  = 0; //最高値、最安値の参照期間の単位。
                           //1:PERIOD_M1, 2:PERIOD_M5, 3:PERIOD_M15, 4:PERIOD_M30, 5:PERIOD_H1, 6:PERIOD_H4
                           //7:PERIOD_D1, 8:PERIOD_W1, 9:PERIOD_MN1
extern int PAST_LEN =  12; //最高値、最安値の参照期間

extern double ENTRY_WIDTH_PIPS = 20.0; //エントリーする間隔。PIPS数。
extern double SHORT_ENTRY_WIDTH_PER = 40.0; //ショート実施帯域。過去最高値から何パーセント下までショートするか
extern double LONG_ENTRY_WIDTH_PER  = 40.0;  //ロング実施帯域。過去最安値から何パーセント上までロングするか
extern double EXCLUDE_ENTRY_PER = 10.0;       //過去最高値及び過去最安値から何パーセントまでの間は取引を控えるか
extern double LIMMITMARGINLEVEL = 105.0;    //証拠金維持率がこの数値を下回る場合は取引を控える

extern string TechNoSwitchTitle="---売買判定にテクニカル分析を加味する時はTrue---";
extern bool   TechNoSwitch = true;
extern int    DISTANCE = 2; // ENTRY_WIDTH_PIPS / 2の範囲内の取引を禁ずる。

extern double VT_POSITIVE_SIGMA = 4.0;  // 売買判断に使う。指標の平均 ± nσ内で売買を許可する時のn。
//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
string PGName   = "PuellaTigris　VTSQL_RT";  //プログラム名			
bool mMailFlag  = true;               //定時報告メールの送信フラグ。trueで送信する。

string INI;
string Host, User, Password, Database, Socket; // database credentials
int Port,ClientFlag;
int DB; // database identifier

string global_strategyName = "temp";
int global_stageID = 0;
//int global_TickNo = 0;
//int global_Period4vTrade = PRRIOD_M1;  // 仮想取引登録用の時間軸


//EAを足の更新ごとに実行するための変数。
datetime execVTSQL_RTtime = 0;

//メールの送信制御のための変数
datetime mailTime = 0;


double mMarketInfoMODE_STOPLEVEL = 0.0;
double past_max = 0.0;     //過去の最高値
datetime past_maxTime = 0; //過去の最高値の時間
double past_min = 0.0;     //過去の最安値
datetime past_minTime = 0; //過去の最安値の時間
double past_width = 0.0;   // 過去値幅。past_max - past_min

double mLong_Min = 0.0;  // ロング取引を許可する最小値
double mLong_Max = 0.0;  // ロング取引を許可する最大値
double mShort_Min = 0.0; // ショート取引を許可する最小値
double mShort_Max = 0.0; // ショート取引を許可する最大値


// 取引可能かを判定する際に使用する平均、偏差を格納する構造体
st_vAnalyzedIndex st_vAnalyzedIndexesBUYSELL_Profit;

datetime VTSQLRTtime0;


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

   if(checkExternalParamCOMMON() != true) {
      printf( "[%d]エラー 外部パラメーターに不適切な値あり" , __LINE__);
      return -1;
   }
   if(checkExternalParam() != true) {
      printf( "[%d]エラー 外部パラメーターに不適切な値あり" , __LINE__);
      return -1;
   }
   if(checkGlobalParam() != true) {
      printf( "[%d]エラー 大域変数に不適切な値あり" , __LINE__);
      return -1;
   }
      
   // テスト状態を判定して、start()内では画面処理をしないようにする
   global_IsTesting = IsTesting() ;
   if (global_IsTesting == true) {
   }
   else {
      bool result_flag       = false;                            //処理結果格納用   
      int err_code           = 0;                                //エラーコード取得用				      
      string err_title       = "[オブジェクト生成エラー] ";      //エラーメッセージタイトル			   			
  	
      //画面にＥＡ名を表示させる。
      //ラベルオブジェクト生成(PGName)	
      if(ObjectFind("PGName")!=WindowOnDropped())	{	
         result_flag = ObjectCreate("PGName",OBJ_LABEL,WindowOnDropped(),0,0);	
         if(result_flag == false)  {	
            err_code = GetLastError();	
            printf( "[%d]エラー DB未接続:：%s---%s" , __LINE__ , err_title, ErrorDescription(err_code));
         }	
      }	
      ObjectSet("PGName",OBJPROP_CORNER,3);              //アンカー設定	
      ObjectSet("PGName",OBJPROP_XDISTANCE,3);           //横位置設定	
      ObjectSet("PGName",OBJPROP_YDISTANCE,5);           //縦位置設定	
      ObjectSetText("PGName",PGName,8,"Arial",Gray);     //テキスト設定	
   }


  // PAST_SPANの設定値が取りうる値かどうかをチェックの上、MQL4の定数に変換する。
   if(PAST_SPAN < 0 || PAST_SPAN > 9) {
      PAST_SPAN = 0;
   }
   switch(PAST_SPAN) {
      case 1:PAST_SPAN = PERIOD_M1;
      case 2:PAST_SPAN = PERIOD_M5;
      case 3:PAST_SPAN = PERIOD_M15;
      case 4:PAST_SPAN = PERIOD_M30;
      case 5:PAST_SPAN = PERIOD_H1;
      case 6:PAST_SPAN = PERIOD_H4;
      case 7:PAST_SPAN = PERIOD_D1;
      case 8:PAST_SPAN = PERIOD_W1;
      case 9:PAST_SPAN = PERIOD_MN1;
      default:PAST_SPAN = PERIOD_CURRENT;
   }


   // 許容リスクが設定されていれば、ロット数を再計算する。
   if(RISK_PERCENT > 0.0) {
      double lotSize = calcLotSizeRiskPercent(AccountFreeMargin(), global_Symbol, SL_PIPS, RISK_PERCENT);
      if(lotSize > 0.0) {
         LOTS = lotSize;
      }
   }
   


//---
   return(INIT_SUCCEEDED);  
}


//+------------------------------------------------------------------+	
//| メイン処理                                                       |	
//+------------------------------------------------------------------+	
int start() {
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

if(TimeCurrent() - execVTSQL_RTtime >= UpdateMinutes * 60) {
//printf( "[%d]テスト 基準日時=%s" , __LINE__, TimeToStr(TimeCurrent()));

   if(checkExternalParamCOMMON() != true) {
      printf( "[%d]エラー 外部パラメーターに不適切な値あり" , __LINE__);
      return ERROR;
   }
   if(checkExternalParam() != true) {
      printf( "[%d]エラー 外部パラメーターに不適切な値あり" , __LINE__);
      return ERROR;
   }
   if(checkGlobalParam() != true) {
      printf( "[%d]エラー 内部パラメーターに不適切な値あり" , __LINE__);
      return ERROR;
   }   

   //変数宣言　　	
   bool result_flag       = false;                            //処理結果格納用   
   int type               = OP_BUY;                           //売買区分   
   string comment         = "";                               //オーダーコメント格納用				   
   color arrow_color      = CLR_NONE;                         //色	   
   int i                  = 0;                                //汎用カウンタ   
   int x                  = 0;                                //汎用カウンタ   
   int err_code           = 0;                                //エラーコード取得用				      
   string err_title       = "[オブジェクト生成エラー] ";      //エラーメッセージタイトル			   			

   //関数の本体呼び出し。
   even_intervals(global_Symbol);

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、全オーダーの指値と逆指値をセットする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      setAllOrdersTPSL(MagicNumberVTSQLRT, TP_PIPS, SL_PIPS);
   } 

   //最小利食値FLOORINGが設定されていれば、損切値の更新を試す。
   if(FLOORING >= 0) {
      flooringSL(MagicNumberVTSQLRT, FLOORING);
   }

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、マジックナンバーをキーとして強制決済をする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      doForcedSettlement(MagicNumberVTSQLRT, global_Symbol, TP_PIPS, SL_PIPS);
   } 

   execVTSQL_RTtime = TimeCurrent();

  //毎時MAILTIME分に損益メールを送信する。
   if (global_IsTesting == true) {
   }
   else {	
      if(TimeCurrent() > mailTime + MAILTIME*60) {  
         SendMailOrg2(30);
         mailTime = TimeCurrent();
      }
   }
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
   
   //オブジェクトの削除	
   ObjectDelete("Long_Max");
   ObjectDelete("Long_Min");
   ObjectDelete("Short_Max");
   ObjectDelete("Short_Min");   
   ObjectDelete("PGName");	
//---
   return(1);  
}
 
//スクリプト開始


//+------------------------------------------------------------------+
//|   even_intervals()                                               |
//+------------------------------------------------------------------+  

int even_intervals(string symbol) {

   bool open_flag  = false;  // 新規取引してよければ、true
   bool exist_flag = false;  // 近い値の取引が存在していれば、true.
   bool index_flag = false;  // 現時点の指標が、過去指標の平均、偏差を満たしていればtrue

   double tp = 0.0;
   int orderNum = 0;

   // 評価時点のASK、BIDを取得する。
   double mMarketinfoMODE_ASK = MarketInfo(symbol,MODE_ASK);
   double mMarketinfoMODE_BID = MarketInfo(symbol,MODE_BID);
 
   double mMarketinfoMODE_POINT = global_Points;
   int mIndex = 0;
   mIndex = iHighest(            // 指定した通貨ペア・時間軸の最高値インデックスを取得
             symbol,   // 通貨ペア
             PAST_SPAN,  // 時間軸 
             MODE_HIGH,  // データタイプ[高値を指定]
             PAST_LEN,         // 検索カウント。時間軸PAST_SPANをPAST_LEN個参照する。
             1           // 開始インデックス
   );
      
   if(mIndex > 0) {
           past_max = iHigh(           // 指定した通貨ペア・時間軸の高値を取得
                           symbol,   // 通貨ペア
                           PAST_SPAN,  // 時間軸 
                           mIndex      // インデックス[iHighestで取得したインデックスを指定]
           );
           past_maxTime = iTime(symbol, PAST_SPAN, mIndex);
   }
   
   mIndex = 0;
   mIndex = iLowest(            // 指定した通貨ペア・時間軸の最高値インデックスを取得
             symbol,   // 通貨ペア
             PAST_SPAN,  // 時間軸 
             MODE_LOW,  // データタイプ[安値を指定]
             PAST_LEN,         // 検索カウント。時間軸PAST_SPANをPAST_LEN個参照する。
             1           // 開始インデックス
   );
   if(mIndex > 0) {
           past_min = iLow(           // 指定した通貨ペア・時間軸の高値を取得
                           symbol,   // 通貨ペア
                           PAST_SPAN,  // 時間軸 
                           mIndex      // インデックス[iHighestで取得したインデックスを指定]
           );
           past_minTime = iTime(symbol, PAST_SPAN, mIndex);
   }
  
   //過去値幅past_widthを、最高値past_max - 最安値past_minとする。
   past_width = past_max - past_min;

//
//ロング取引及びショート取引を許可する価格帯をグローバル変数に設定する。 
//気配値が、上限または下限に近いときは、新規取引はしない
//past_width = past_max - past_min
//past_max  -----------------------------------------------------
//             ↓      EXCLUDE_MAX_PER （取引不能）
//mShort_Max-----------------------------------------------------
//             → SHORT_ENTRY_WIDTH_PER (ショート実行可能)
//mShort_Min-----------------------------------------------------
//　　　　　　　　　　　取引不能
//                
//mLong_Max -----------------------------------------------------
//             → LONG_ENTRY_WIDTH_PER (ロング実行可能)
//mLomg_Min-----------------------------------------------------
//             ↑      EXCLUDE_LOWER_PER（取引不能）
//past_min  -----------------------------------------------------

   // 現在値が、過去最高値から、過去最安値と最高値の価格帯のEXCLUDE_LOWER_PER％下をショート上限とする。
   mShort_Max = past_max - past_width * EXCLUDE_ENTRY_PER / 100; 
   // 現在値が、過去最高値から、過去最安値と最高値の価格帯のSHORT_ENTRY_WIDTH_PER％下をロング下限とする。
   mShort_Min = past_max - past_width * SHORT_ENTRY_WIDTH_PER / 100; 
   // 現在値が、過去最安値から、過去最安値と最高値の価格帯のLONG_ENTRY_WIDTH_PER％上をロング上限とする。
   mLong_Max =  past_min + past_width * LONG_ENTRY_WIDTH_PER / 100; 
   // 現在値が、過去最安値から、過去最安値と最高値の価格帯のEXCLUDE_LOWER_PER％上をロング下限とする。
   mLong_Min =  past_min + past_width * EXCLUDE_ENTRY_PER / 100; 
   if(ShowTestMsg == true) printf( "[%d]テスト ロングpast_max:：%s" , __LINE__ , DoubleToStr(past_max));
   if(ShowTestMsg == true) printf( "[%d]テスト ロングpast_max:：%s" , __LINE__ , DoubleToStr(past_min));

   if(IsTesting() == true) {
      // バックテスト時は、描画処理をしない。
   }
   else {
      // ロング上限に線を引く
      ObjectDelete("Long_Max");
      ObjectCreate("Long_Max",OBJ_HLINE,0,0,mLong_Max);
      ObjectSet("Long_Max",OBJPROP_COLOR,clrMediumVioletRed);
      ObjectSet("Long_Max",OBJPROP_WIDTH,3);
      if(ShowTestMsg == true) printf( "[%d]テスト ロング上限:：%s" , __LINE__ , DoubleToStr(mLong_Max));
      
      // ロング下限に線を引く
      ObjectDelete("Long_Min");
      ObjectCreate("Long_Min",OBJ_HLINE,0,0,mLong_Min);
      ObjectSet("Long_Min",OBJPROP_COLOR,clrMediumVioletRed);
      ObjectSet("Long_Min",OBJPROP_WIDTH,3);
      if(ShowTestMsg == true) printf( "[%d]テスト ロング下限:：%s" , __LINE__ , DoubleToStr(mLong_Min));
     
      // ショート上限に線を引く
      ObjectDelete("Short_Max");
      ObjectCreate("Short_Max",OBJ_HLINE,0,0,mShort_Max);
      ObjectSet("Short_Max",OBJPROP_COLOR,clrMediumVioletRed);
      ObjectSet("Short_Max",OBJPROP_WIDTH,3);
      if(ShowTestMsg == true) printf( "[%d]テスト ショート上限:：%s" , __LINE__ , DoubleToStr(mShort_Max));
      
      // ショート下限に線を引く
      ObjectDelete("Short_Min");
      ObjectCreate("Short_Min",OBJ_HLINE,0,0,mShort_Min);
      ObjectSet("Short_Min",OBJPROP_COLOR,clrMediumVioletRed);
      ObjectSet("Short_Min",OBJPROP_WIDTH,3);   
      if(ShowTestMsg == true) printf( "[%d]テスト ショート下限:：%s" , __LINE__ , DoubleToStr(mShort_Min));
   }
   
   
   //
   //ロング、ショートの可否を
   //①取引可能な価格帯か
   //②価格帯を等分した時のいずれかの境界値に近いか
   //という視点で判断する。
   
   //ロングのオープン手順
   //①ASKが、mLong_Max　～　mLong_Minの間であること。
   //②ASKが、過去最高値と過去最安値をエントリー間隔ENTRY_WIDTH_PIPSで分割した時のいずれかの境界値に近いこと。
   //③スプレッドASK-BIDが、MAX_SPREAD_POINT未満であること。
   
   //過去最高値と過去最安値をエントリー間隔ENTRY_WIDTH_PIPSで分割した時の直近の取引可能価格
   double nearTradablePrice = getNearTradablePrice(symbol, mMarketinfoMODE_ASK);
   double adjustValue = global_Points;
   if( VTSQLRTtime0 != Time[0]   //連続取引の制限
       &&
      (mLong_Min > 0.0 && mLong_Max > 0.0 && NormalizeDouble(mLong_Max, global_Digits) > NormalizeDouble(mLong_Min, global_Digits) )  // 取引可能価格帯の上限と下限が意味のある値であること
       &&
      (NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) > NormalizeDouble(mLong_Min, global_Digits) 
         && NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) < NormalizeDouble(mLong_Max, global_Digits) )  //①ASKが範囲内にあること
       &&
      (nearTradablePrice > 0.0 && 
         MathAbs(NormalizeDouble(nearTradablePrice, global_Digits) - NormalizeDouble(mMarketinfoMODE_ASK, global_Digits)) / NormalizeDouble(adjustValue, global_Digits) < NormalizeDouble(ENTRY_WIDTH_PIPS / DISTANCE, global_Digits) )
       //②直近の取引可能価とのずれがENTRY_WIDTH_PIPS（エントリーする間隔。PIPS数。）の半分未満であること
    ) {  
    
      // オープンフラグopen_flagをfalseに初期設定する。
      open_flag = false;

      // ロングを許可するのは、①近い値で取引がされていないこと。②指標が平均、偏差を満たしていること。
      // ①関数exist_flag = find_Same_Entry(magic, OP_BUY, ASK)を使ってオープン中の取引を探し、
      // 　同じOP_BUYの取引が存在しないこと。
      exist_flag = find_Same_Entry(MagicNumberVTSQLRT, symbol, OP_BUY, mMarketinfoMODE_ASK);

      // ②関数index_flag = checkIndexes(Time[0], BUY_PROFIT)を使って、現時点Time[0]の指標が
      //   過去の仮想取引から求めた平均、偏差の範囲内であること。
      index_flag = checkIndexes(symbol,    // 通貨ペア
                                PERIOD_M15, // vAnalyzedIndexの指標計算に使った時間軸
                                OP_BUY, // OP_BUY, OP_SELL
                                vPROFIT,    // vPROFIT, vLOSS
                                Time[0]  // 指標を計算する現時点の時間
                                );

      if(exist_flag == false && index_flag == true) {
         open_flag = true;
      }
      else {
         open_flag = false;
      }      

      // オープンフラグopen_flagがtrueであれば、ロング取引を送信する。
      if(open_flag == true) {
         int ticket_num = -1;
         bool mBuyable = checkMargin(symbol, OP_BUY, LOTS, LIMMITMARGINLEVEL);
         if(VTSQLRTtime0 != Time[0] && mBuyable == true) {
            ticket_num = mOrderSend4(symbol,OP_BUY,LOTS,mMarketinfoMODE_ASK,SLIPPAGE,0.0,0.0,"VTSQLRT",MagicNumberVTSQLRT,0,LINE_COLOR_LONG);
            if( ticket_num > 0) { 
               VTSQLRTtime0 = Time[0];
            }
            else {
               printf( "[%d]エラー 買い発注の失敗:：%s" , __LINE__ , GetLastError());
            }
         }
      }  // if(open_flag == true) {
   }     // if( VTSQLRTtime0 != Time[0]   //連続取引の制限


   //ショートのオープン手順
   //①BIDが、mShort_Max　～　mShort_Minの間であること。
   //②BIDが、過去最高値と過去最安値をエントリー間隔ENTRY_WIDTH_PIPSで分割した時のいずれかの境界値に近いこと。
   //③スプレッドASK-BIDが、MAX_SPREAD_POINT未満であること。

   //過去最高値と過去最安値をエントリー間隔ENTRY_WIDTH_PIPSで分割した時の直近の境界値
   nearTradablePrice = getNearTradablePrice(symbol, mMarketinfoMODE_BID);

   if( VTSQLRTtime0 != Time[0] &&  //連続取引の制限
      (mShort_Min > 0.0 && mShort_Max > 0.0 && NormalizeDouble(mShort_Max, global_Digits) > NormalizeDouble(mShort_Min, global_Digits))  // 取引可能価格帯の上限と下限が意味のある値であること
      &&
      (NormalizeDouble(mMarketinfoMODE_BID, global_Digits) > NormalizeDouble(mShort_Min, global_Digits) && NormalizeDouble(mMarketinfoMODE_BID, global_Digits) < NormalizeDouble(mShort_Max, global_Digits))  //①BIDが範囲内にあること
      &&
      (nearTradablePrice > 0.0 && MathAbs(NormalizeDouble(nearTradablePrice, global_Digits) - NormalizeDouble(mMarketinfoMODE_BID, global_Digits)) / adjustValue < NormalizeDouble(ENTRY_WIDTH_PIPS / DISTANCE, global_Digits) )
     ) {  
      // オープンフラグopen_flagをfalseに初期設定する。
      open_flag = false;
      exist_flag = false;

      // ロングを許可するのは、①近い値で取引がされていないこと。②指標が平均、偏差を満たしていること。
      // ①関数exist_flag = find_Same_Entry(magic, OP_BUY, ASK)を使ってオープン中の取引を探し、
      // 　同じOP_BUYの取引が存在しないこと。
      exist_flag = find_Same_Entry(MagicNumberVTSQLRT, symbol, OP_BUY, mMarketinfoMODE_ASK);



      // ショートを許可するのは、①近い値で取引がされていないこと。②指標が平均、偏差を満たしていること。
      // ①関数find_Same_Entry(magic, OP_SELL, BID)を使ってオープン中の取引を探し、
      // 　同じOP_SELLの取引が存在しないこと。
      exist_flag = find_Same_Entry(MagicNumberVTSQLRT, symbol, OP_SELL, mMarketinfoMODE_BID);

      // ②関数index_flag = checkIndexes(Time[0], SELL_PROFIT)を使って、現時点Time[0]の指標が
      //   過去の仮想取引から求めた平均、偏差の範囲内であること。
      index_flag = checkIndexes(symbol,    // 通貨ペア
                                PERIOD_M15, // vAnalyzedIndexの指標計算に使った時間軸
                                OP_SELL, // OP_BUY, OP_SELL
                                vPROFIT,    // vPROFIT, vLOSS
                                Time[0]  // 指標を計算する現時点の時間
                                );

      if(exist_flag == false) {
         open_flag = true;
      }
      else {
         open_flag = false;
      }      

      
      int ticket_num = -1;      

     // オープンフラグopen_flagがtrueであれば、ショート取引を送信する。
      if(open_flag == true) {
         bool mSellable = checkMargin(symbol, OP_SELL, LOTS, LIMMITMARGINLEVEL);
   
         if(VTSQLRTtime0 != Time[0] && mSellable == true) {
            ticket_num = mOrderSend4(symbol,OP_SELL,LOTS,mMarketinfoMODE_BID,SLIPPAGE,0.0,0.0,"VTSQLRT",MagicNumberVTSQLRT,0,LINE_COLOR_SHORT);
            if(ticket_num > 0) { 
               VTSQLRTtime0 = Time[0];
            }
            else {
               printf( "[%d]エラー 買い発注の失敗:：%s" , __LINE__ , GetLastError());
            }
         }
      }
   }
   return 0;//正常終了
}



//=========================================================================
//関数find_Same_Entry(マジックナンバーmagic, 売買区分buysell, 発注予定額price)
//マジックナンバー、売買区分、発注金額を持つオープン中の取引があれば、trueを返す。
//上記以外はfalseを返す。
//オープン中の取引の中に、マジックナンバーがmagic, 売買区分がbuysell, 
//かつ、発注予定額がオープンな取引の約定値に近ければ（※）、同じ価格での取引が存在すると判断して、
//trueを返す。
//上記以外は、falseを返す。
//（※）滑ることを考えて、発注予定額と候補取引の約定値の差が、ENTRY_WIDTH_PIPS（エントリーする間隔。PIPS数。）の
//      半分未満(DISTANCE=2)であれば、発注予定額が候補取引の約定値に近いと判断する。
bool find_Same_Entry(int magic, string symbol, int buysell, double price) {
int mMagic     = 0;
int mBUYSELL   = 0;	
double mOpen   = 0.0;	
string mSymbol = "";
//double diff = ENTRY_DIFF_PIPS * 
double adjustValue = global_Points;

   for(int i = OrdersTotal() - 1; i >= 0;i--) {						
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == true) {
         mMagic = OrderMagicNumber(); 				
         mBUYSELL = OrderType();	
         mOpen = OrderOpenPrice();
	      mSymbol = OrderSymbol();
         
         if( mMagic == magic && mSymbol == symbol && mBUYSELL == buysell) {
            if( MathAbs(mOpen-price) < (ENTRY_WIDTH_PIPS * adjustValue) / DISTANCE  ) {
               return true;
            }  
         }

      }	
   }	
   return false;	
}	

  

int getOrderNum(int magic, string symbol, int buysell) {
int mMagic     = 0;
int mBUYSELL   = 0;	
string mSymbol = "";
int count = 0;

//return false;	
   for(int i = OrdersTotal() -1; i >= 0;i--) {						
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == true) {
         mMagic = OrderMagicNumber();
         mBUYSELL = OrderType();	
         mSymbol = OrderSymbol();
   	               
         if( mMagic == magic  && mSymbol == symbol && mBUYSELL == buysell) {
            count = count + 1;
         }  
      }
   }

   return count;	
}	






//=========================================================================
// 引数mTargetDT時点の指標を計算し、それが、DBに登録された過去取引から計算した平均、偏差の範囲内であればtrueを返す。
// DBから取得する値は、登録データ中最大のステージのデータのうち、通貨ペア、時間軸、売買区分、損益フラグが一致し、
// analyzeTimeがmTargetDT以前で最大のもの
bool checkIndexes(string   mSymbol,    // 通貨ペア
                  int      mTimeframe, // vAnalyzedIndexの指標計算に使った時間軸
                  int      mOrderType, // OP_BUY, OP_SELL
                  int      mPLFlag,    // vPROFIT, vLOSS
                  datetime mTargetDT   // 指標を計算する現時点の時間
                  ) {

   st_vOrderIndex buf_st_vOrderIndexes;  // 計算した指標を格納する構造体。
   bool flag_do_calc_Indexes = do_calc_Indexes(mSymbol,              // 入力：通貨ペア
                                               mTimeframe,           // 入力：指標の計算に使う時間軸。PERIOD_M1, PERIOD_M5など
                                               mTargetDT,            // 入力：計算基準時間。datatime型。
                                               buf_st_vOrderIndexes  // 出力：指標の計算結果。
                                               );
   if(flag_do_calc_Indexes == false) {
      printf( "[%d]エラー 　%s時点の指標計算失敗" , __LINE__, TimeToStr(mTargetDT));
      return false;
   }

   bool flag_get_st_vAnalyzedIndexes = 
        DB_get_st_vAnalyzedIndexesBUYSELL_Profit(mSymbol,              // 入力：通貨ペア
                                                 mTimeframe,           // 入力：指標の計算に使う時間軸。PERIOD_M1, PERIOD_M5など
                                                 mTargetDT,            // 入力：計算基準時間。datatime型。
                                                 mOrderType,
                                                 mPLFlag,    // vPROFIT, vLOSS
                                                 st_vAnalyzedIndexesBUYSELL_Profit  // 出力：テーブルから読み込んだ平均、偏差
                                               );
   if(flag_get_st_vAnalyzedIndexes == false) {
      printf( "[%d]エラー 　%s用の平均、偏差の取得失敗" , __LINE__, TimeToStr(mTargetDT));
      return false;
   }

   bool insideFlag = false;
   if(mOrderType == OP_BUY && mPLFlag == vPROFIT) {
      insideFlag = isInsideOf(st_vAnalyzedIndexesBUYSELL_Profit,  // 平均、偏差を含む構造体 
                              VT_POSITIVE_SIGMA, 
                              buf_st_vOrderIndexes);
   }
   else if(mOrderType == OP_SELL && mPLFlag == vPROFIT) {
      insideFlag = isInsideOf(st_vAnalyzedIndexesBUYSELL_Profit,  // 平均、偏差を含む構造体 
                              VT_POSITIVE_SIGMA, 
                              buf_st_vOrderIndexes);
   }
   else {   // 上記以外は、判定対象外
      insideFlag = false;
   }

   return insideFlag;
}


//=========================================================================
// 引数の通貨ペア、時間軸を持つvAnalyzedIndexesデータのうち、
// ステージは最大値、analyzeTimeは基準時間mTargetDT以下直近（降順に並べた最初）のデータを読み込み、
// 出力用引数st_vAnalyzedIndexesBUYSELL_Profitにセットする。
bool DB_get_st_vAnalyzedIndexesBUYSELL_Profit(string            mSymbol,              // 入力：通貨ペア
                                              int               mTimeframe,           // 入力：指標の計算に使う時間軸。PERIOD_M1, PERIOD_M5など
                                              datetime          mTargetDT,            // 入力：計算基準時間。datatime型。
                                              int               mOrderType,
                                              int               mPLFlag,    // vPROFIT, vLOSS
                                              st_vAnalyzedIndex &m_vAnalyzedIndexesBUYSELL_Profit  // 出力：テーブルから読み込んだ平均、偏差
                                           ) {

   // 出力用引数の初期化
   init_st_vAnalyzedIndexes(m_vAnalyzedIndexesBUYSELL_Profit);

   // 引数のチェック
   if(StringLen(mSymbol) <= 0) {
      return false;
   }
   if(mTimeframe < 0) {
      return false;
   }
   if(mOrderType != OP_BUY && mOrderType != OP_SELL) {
      return false;
   }
   if(mPLFlag != vPROFIT && mPLFlag != vLOSS) {
      return false;
   }

   string Query = "";
   Query = "select * from vAnalyzedIndex where ";
 //  Query = Query + " strategyID  = \'" + st_BS_PL.strategyID + "\' AND ";
   Query = Query + " symbol      = \'" + mSymbol + "\' AND ";
   Query = Query + " timeframe   = " + IntegerToString(mTimeframe) + " AND ";
   Query = Query + " orderType   = " + IntegerToString(mOrderType) + " AND ";
   Query = Query + " PLFlag      = " + IntegerToString(mPLFlag) + " AND ";
   Query = Query + " analyzeTime <= " + IntegerToString(mTargetDT)   + " ";
   Query = Query + " order by stageID DESC, analyzeTime DESC;";  // stageID, analyzeTimeの降順にすることで、最大のステージ番号で、直近のanalyzeTimeが1件目になる
printf( "[%d]テスト　平均、偏差取得用SQL:%s" , __LINE__, Query);  
   
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
         MySqlCursorFetchRow(intCursor);  
         m_vAnalyzedIndexesBUYSELL_Profit.stageID     = MySqlGetFieldAsInt(intCursor, 0);
         if(m_vAnalyzedIndexesBUYSELL_Profit.stageID == 0) {
            printf( "[%d]テスト ステージ0の指標を利用しており、精度は低い" , __LINE__);
         }
         m_vAnalyzedIndexesBUYSELL_Profit.strategyID  = MySqlGetFieldAsString(intCursor, 1);
         m_vAnalyzedIndexesBUYSELL_Profit.symbol      = MySqlGetFieldAsString(intCursor, 2);
         m_vAnalyzedIndexesBUYSELL_Profit.timeframe   = MySqlGetFieldAsInt(intCursor, 3);
         m_vAnalyzedIndexesBUYSELL_Profit.orderType   = MySqlGetFieldAsInt(intCursor, 4);
         m_vAnalyzedIndexesBUYSELL_Profit.PLFlag      = MySqlGetFieldAsInt(intCursor, 5);
         m_vAnalyzedIndexesBUYSELL_Profit.analyzeTime = MySqlGetFieldAsInt(intCursor, 6);
                                                                 // MySqlGetFieldAsInt(intCursor, 7);
         m_vAnalyzedIndexesBUYSELL_Profit.MA_GC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 8), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.MA_GC_SIGMA      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 9), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.MA_DC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 10), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.MA_DC_MEAN       = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 11), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.MA_Slope5_MEAN   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 12), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.MA_Slope5_SIGMA  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 13), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.MA_Slope25_MEAN  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 14), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.MA_Slope25_SIGMA = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 15), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.MA_Slope75_MEAN  = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 16), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.MA_Slope75_SIGMA = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 17), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.BB_Width_MEAN    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 18), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.BB_Width_SIGMA   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 19), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.IK_TEN_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 20), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.IK_TEN_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 21), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.IK_CHI_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 22), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.IK_CHI_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 23), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.IK_LEG_MEAN      = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 24), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.IK_LEG_SIGMA     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 25), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.MACD_GC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 26), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.MACD_GC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 27), global_Digits);                  
         m_vAnalyzedIndexesBUYSELL_Profit.MACD_DC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 28), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.MACD_DC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 29), global_Digits);                  
         m_vAnalyzedIndexesBUYSELL_Profit.RSI_VAL_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 30), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.RSI_VAL_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 31), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.STOC_VAL_MEAN    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 32), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.STOC_VAL_SIGMA   = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 33), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.STOC_GC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 34), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.STOC_GC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 35), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.STOC_DC_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 36), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.STOC_DC_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 37), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.RCI_VAL_MEAN     = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 38), global_Digits);
         m_vAnalyzedIndexesBUYSELL_Profit.RCI_VAL_SIGMA    = NormalizeDouble(MySqlGetFieldAsDouble(intCursor, 39), global_Digits);
      }
   }
   MySqlCursorClose(intCursor);

   return retFlag;
}

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|   共通関数　　　                                                 |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+





//+------------------------------------------------------------------+
//| 最寄りの取引可能価格を検索する                   　　　　　      |
//+------------------------------------------------------------------+
/*
past_max（過去の最高値）とpast_min（過去の最安値）を
ENTRY_WIDTH_PIPS（エントリーする間隔。PIPS数。）で区切ったとして、
入力された現在価格との絶対値が最も小さい価格を返す。
エラー時は、0を返す。
*/
double getNearTradablePrice(string symbol, double currPrice){
   double diffValue_MIN = ERROR_VALUE_DOUBLE; //差額の最小値。起こり得ない数値を初期値とする。
   double adjustValue = 0.0;   //通貨別の桁数調整。0.01か0.0001
   int    borderNum = 0;      //過去の最高値と最安値の間に何本の取引可能値があるか。
   double tmpborderPrice = 0.0;  //取引可能値（途中計算用）
   double borderPrice = 0.0;  //取引可能値（返り値用）

   if(currPrice <= 0.0) {
      return 0.0;
   }

   adjustValue = global_Points;
   if(adjustValue <= 0.0) {
      return 0.0;
   }

   borderNum = (int)((NormalizeDouble(past_max, global_Digits) - NormalizeDouble(past_min, global_Digits)) / (ENTRY_WIDTH_PIPS * adjustValue) ) - 1;
printf( "[%d]テスト past_max=%s と　past_min=%sをENTRY_WIDTH_PIPS=%sで分割し、%d個の候補を作る" , __LINE__ , 
          DoubleToStr(past_max, global_Digits),
          DoubleToStr(past_min, global_Digits),
          DoubleToStr(ENTRY_WIDTH_PIPS * adjustValue, global_Digits),
          borderNum);
   for(int i = 1; i < borderNum; i++) {
      tmpborderPrice = NormalizeDouble(past_max, global_Digits) - i * (ENTRY_WIDTH_PIPS * adjustValue);
      if( (tmpborderPrice > 0.0)
         && MathAbs(NormalizeDouble(diffValue_MIN, global_Digits)) > MathAbs(NormalizeDouble(tmpborderPrice, global_Digits) - NormalizeDouble(currPrice, global_Digits))) {
         diffValue_MIN = NormalizeDouble(borderPrice, global_Digits) - NormalizeDouble(currPrice, global_Digits);
         borderPrice = tmpborderPrice;
      }
      if(tmpborderPrice < 0.0) {
         break;
      }
   }

   if(borderPrice < 0.0) {
      return 0.0;
   }
   else {
      return borderPrice;
   }
}

//+------------------------------------------------------------------+
//| 取引可能な範囲内にあるBID値のリストを返す。      　　　　　      |
//+------------------------------------------------------------------+
/*
past_max（過去の最高値）とpast_min（過去の最安値）を
ENTRY_WIDTH_PIPS（エントリーする間隔。PIPS数。）で区切ったとして、
取引可能な範囲内にあるBID値のリストを返す。
エラー時は、""を返す。
*/
string getNearTradablePriceList(string symbol){
   string retBuf = "";
   string retBufLong = "";
   string retBufSort = "";
   double diffValue_MIN = ERROR_VALUE_DOUBLE; //差額の最小値。起こり得ない数値を初期値とする。
   double adjustValue = 0.0;   //通貨別の桁数調整。0.01か0.0001
   int    borderNum = 0;      //過去の最高値と最安値の間に何本の取引可能値があるか。
   double tmpborderPrice = 0.0;  //取引可能値（途中計算用）
   double borderPrice = 0.0;  //取引可能値（返り値用）

   adjustValue = global_Points;
   if(adjustValue <= 0.0) {
      return retBuf;
   }

   borderNum = (int)((past_max - past_min) / (ENTRY_WIDTH_PIPS * adjustValue) ) - 1;
printf( "[%d]テスト past_max=%s と　past_min=%sをENTRY_WIDTH_PIPS=%sで分割し、%d個の候補を作る" , __LINE__ , 
          DoubleToStr(past_max, global_Digits),
          DoubleToStr(past_min, global_Digits),
          DoubleToStr(ENTRY_WIDTH_PIPS * adjustValue, global_Digits),
          borderNum);

   for(int i = 1; i < borderNum; i++) {
      // past_maxから、i番目のエントリー候補となる値
      tmpborderPrice = past_max - i * (ENTRY_WIDTH_PIPS * adjustValue);

      // i番目のエントリー候補となる値が、
      // ロングの範囲 （mLong_Max以下かつmLong_Min以上）または、
      // ショートの範囲(mShort_Max以下かつmShort_Min以上）
      // であれば、返り値のリストに追加する。
      if(  (tmpborderPrice <= mLong_Max && tmpborderPrice >= mLong_Min) ){
        // retBufLong = retBufLong + "  ロング候補 >" + DoubleToString(tmpborderPrice, global_Digits) + "<" + "mLong_Min=" +  DoubleToString(mLong_Min, global_Digits)  + "mLong_Max=" +  DoubleToString(mLong_Max, global_Digits)+ "\n";
         retBufLong = retBufLong + "  ロング候補 >" + DoubleToString(tmpborderPrice, global_Digits) + "<" + "\n";

      }
      else if(  (tmpborderPrice <= mShort_Max && tmpborderPrice >= mShort_Min)) {
       //  retBufSort = retBufSort + "ショート候補 >" + DoubleToString(tmpborderPrice, global_Digits) + "<" + "mShort_Min=" +  DoubleToString(mShort_Min, global_Digits)  + "mShort_Max=" + DoubleToString(mShort_Max, global_Digits)+ "\n";
         retBufSort = retBufSort + "ショート候補 >" + DoubleToString(tmpborderPrice, global_Digits) + "<"  + "\n";
      }
   }
   retBuf = retBufLong + "\n" + retBufSort;
   return retBuf;
}




//+------------------------------------------------------------------+
//|   定時メール送信                                                 |
//+------------------------------------------------------------------+	
void SendMailOrg2(int mailtime1) { 
   int mMinute = Minute();
   double EvenIntwin = 0.0;
   double Otherswin = 0.0;
    
   double EvenIntlose = 0.0;
   double Otherslose = 0.0;
   
   int    bufMagicNumber = 0;
   
   double EvenIntRate = 0.0;
   double OthersRate = 0.0;
   string bufOthers = "";
   
   if( (mMinute  != mailtime1) || (mMailFlag  != true) ){
      return ;
   }			


   string strSubject = "";
   string strBody    = "";
   double mWin = 0.0;        //勝ち数
   double mLose = 0.0; 	  //負け数
   double mDraw = 0.0;	  //引き分け数
   double mPFWin = 0.0;      //実現利益。プロフィットファクタ計算用。
   double mPFLose = 0.0;	  //実現損失。プロフィットファクタ計算用。
   double mPF = 0.0;	  //プロフィットファクタ。
   bool doneFlag = false;         //決済フラグ
   double latentLoss = 0.0;  //含み損
   double latentProf = 0.0;  //含み益	   				
   double mProfLoss = 0.0;   //実現損益。

   MqlDateTime server, trade;
   TimeCurrent(server);
   	
   int year  = server.year;  //プログラム実行時の年
   int month = server.mon;   //プログラム実行時の月
   int day   = server.day;   //プログラム実行時の日
	
   int orderType = 0;
   double orderProf = 0.0;

   TimeToStruct(OrderCloseTime(), trade);	

   for(int j = OrdersHistoryTotal() - 1; j >= 0; j--){					
      if(OrderSelect(j, SELECT_BY_POS, MODE_HISTORY) == false) {
         break;				
      }
      
      // 当日の取引データを使った計算
      if( (trade.year == year) && (trade.mon  == month) && (trade.day  == day)) {	//実行年月日の取引データを集計する。
	 orderType = OrderType();
         orderProf = OrderProfit();
         if( (orderType == OP_BUY) || (orderType == OP_SELL) ){  	
            bufMagicNumber = OrderMagicNumber();
            mProfLoss = mProfLoss + orderProf;		
	         if(orderProf > 0) {			
 	            mWin = mWin + 1;		
		         mPFWin = mPFWin + orderProf;	
               if(bufMagicNumber == MagicNumberVTSQLRT) {
      		      EvenIntwin = EvenIntwin + 1;
	            }
      	      else {
		            bufOthers = bufOthers + "--" + IntegerToString(bufMagicNumber);
		            Otherswin = Otherswin + 1;
		         } 	
            }		
            else if(orderProf < 0) {			
	            mLose = mLose + 1;			
         	   mPFLose = mPFLose + orderProf;
               if(bufMagicNumber == MagicNumberVTSQLRT) {
                  EvenIntlose = EvenIntlose + 1;
		         }
		         else {
		            Otherslose = Otherslose + 1;
                  bufOthers = bufOthers + "--" + IntegerToString(bufMagicNumber);
		         }
            }			
	         else {			
	            mDraw = mDraw + 1;		
	         }
         }
      }
   }
      
   latentProf = 0.0;	
   latentLoss = 0.0;	
   int j;
   for(j = OrdersTotal() - 1; j >= 0; j--){						
      if(OrderSelect(j, SELECT_BY_POS, MODE_TRADES) == false) {
         break;
      }  
      if(OrderCloseTime() <= 0) {  // CloseTimeが設定されていない＝決済されていない
         doneFlag = false;
      }
      else {
         doneFlag = true;
      }
				
      if(doneFlag == false) {     //オーダーが決済されていない時、含み損益の計算をする。	
   	      orderProf = OrderProfit();			
   	      if(orderProf > 0.0) {		
   	         latentProf = latentProf + orderProf;					
   	      }			
   	      else if(orderProf < 0.0) {
               latentLoss = latentLoss + orderProf;					
            }
            else {			
   	      }
         } //オーダーが決済されていないとき－終了			
      }   //for(j = OrdersTotal() - 1; j >= 0; j--){
   double mWinMonthly  = 0.0;               //当月の勝ち数
   double mLoseMonthly  = 0.0; 	          //当月の負け数
   double mDrawMonthly  = 0.0;	          //当月の引き分け数
   double mProfLossMonthly = 0.0;           //当月の実現損益。
   double EvenIntwinMonthly = 0.0;
   double OtherswinMonthly = 0.0;

   double EvenIntloseMonthly = 0.0;
   double OthersloseMonthly = 0.0;

   double EvenIntRateMonthly = 0.0;
   double OthersRateMonthly = 0.0;
   string bufOthersMonthly = "";
   for(j = OrdersHistoryTotal() - 1; j >= 0; j--){					
      if(OrderSelect(j, SELECT_BY_POS, MODE_HISTORY) == false) break;				
      TimeToStruct(OrderCloseTime(), trade);	
      if( (trade.year == year) && (trade.mon  == month) ) {	//実行年月の取引データを集計する。
         orderType = OrderType();
         orderProf = OrderProfit();
         if( (orderType == OP_BUY) || (orderType == OP_SELL) ){  	
            bufMagicNumber = OrderMagicNumber();
            mProfLossMonthly = mProfLossMonthly + orderProf;		
            if(orderProf > 0) {			
               mWinMonthly  = mWinMonthly  + 1;		
               if(bufMagicNumber == MagicNumberVTSQLRT) {
	               EvenIntwinMonthly = EvenIntwinMonthly + 1;
	            }
               else  {
                  OtherswinMonthly = OtherswinMonthly + 1;
               } 	
            }
            else if(orderProf < 0) {			
               mLoseMonthly  = mLoseMonthly  + 1;			
               if(bufMagicNumber == MagicNumberVTSQLRT) {
                  EvenIntloseMonthly = EvenIntloseMonthly + 1;
	            }
               else {
                  OthersloseMonthly = OthersloseMonthly + 1;
               } 	         		      	        
            } 
            else {			
	            mDrawMonthly  = mDrawMonthly  + 1;		
            }			
         }
      }				
   }  // for(j = OrdersHistoryTotal() - 1; j >= 0; j--){

   strSubject = "サーバ名:" + MachineName + ":" + IntegerToString(AccountNumber()) + "："+ PGName + "：" + IntegerToString(TimeYear(TimeLocal())) + "年" + IntegerToString(TimeMonth(TimeLocal()))+ "月" + IntegerToString(TimeDay(TimeLocal()))+ "日　" + IntegerToString(TimeHour(TimeLocal()))+ "時" + IntegerToString(TimeMinute(TimeLocal()))+"分のお知らせ";
   strBody    = strBody + DoubleToStr(mWin, 0) + "勝" + DoubleToStr(mLose, 0) + "敗" + DoubleToStr(mDraw, 0) + "分" + "\n";			
   //勝率の計算  	
   double mWinLose = 0.0;
   string bufWinLose = "";
   if((mWin + mLose + mDraw) != 0) {					
      mWinLose = (mWin / (mWin + mLose + mDraw)) * 100;					
   }
   else {
      mWinLose = 0.0;
   }

   if( EvenIntwin + EvenIntlose != 0) {
      EvenIntRate = EvenIntwin / (EvenIntwin + EvenIntlose);
      bufWinLose = bufWinLose + "--EvenInt      ="+ DoubleToStr(EvenIntwin + EvenIntlose,0)+"戦中勝率"+DoubleToStr(EvenIntRate,2) + "\n";	      }
   else  EvenIntRate = 0.0;
   if( Otherswin + Otherslose != 0) {
      OthersRate = Otherswin / (Otherswin + Otherslose);
      bufWinLose = bufWinLose + "--その他  ="+ bufOthers + "--" + DoubleToStr(Otherswin + Otherslose,0)+"戦中勝率"+DoubleToStr(OthersRate,2) + "\n";
   }
   else  OthersRate = 0.0;
   
   //月次勝率の計算  	
   double mWinLoseMonthly = 0.0;
   string bufWinLoseMonthly = "";
   if((mWinMonthly  + mLoseMonthly  + mDrawMonthly) != 0) {					
      mWinLoseMonthly = (mWinMonthly  / (mWinMonthly  + mLoseMonthly  + mDrawMonthly)) * 100;
   }
   else {
      mWinLoseMonthly = 0.0;
   }

   if( EvenIntwinMonthly + EvenIntloseMonthly != 0) {
      EvenIntRateMonthly = EvenIntwinMonthly / (EvenIntwinMonthly + EvenIntloseMonthly);
      bufWinLoseMonthly = bufWinLoseMonthly + "--MA（月次）     ="+ DoubleToStr(EvenIntwinMonthly + EvenIntloseMonthly,0)+"戦中勝率"+DoubleToStr(EvenIntRateMonthly,2) + "\n";			
   }
   else  EvenIntRateMonthly = 0.0;

   if( OtherswinMonthly + OthersloseMonthly != 0) {
      OthersRateMonthly = OtherswinMonthly / (OtherswinMonthly + OthersloseMonthly);
      bufWinLoseMonthly = bufWinLoseMonthly + "--その他（月次）="+ bufOthersMonthly + "--" + DoubleToStr(Otherswin + OthersloseMonthly,0)+"戦中勝率"+DoubleToStr(OthersRateMonthly,2) + "\n";
   }
   else  OthersRateMonthly = 0.0;
         
   //プロフィットファクターの計算 
   if(mPFLose != 0){
      mPF = mPFWin / (-1* mPFLose);					
   }
   else {
      mPF = 99.99;
   }
   

   strBody = IntegerToString(year) + "年" + IntegerToString(month) + "月" + IntegerToString(day) + "日" + "\n";
   strBody = strBody + "決済損益(月次)＝" + DoubleToStr(mProfLossMonthly, 5) + "\n";
   strBody = strBody + "勝率（月次）= " + DoubleToStr( mWinLoseMonthly,2) + "\n";
   strBody = strBody + bufWinLoseMonthly;
   strBody = strBody + "------------------------" + "\n";

   strBody = strBody + "決済損益(日次)＝" + DoubleToStr(mProfLoss, 5) + "\n";		
   strBody = strBody + "勝率（日次）= " + DoubleToStr( mWinLose,2) + "\n";
   strBody = strBody + bufWinLose;

   strBody = strBody + "------------------------" + "\n";
   strBody = strBody + "PF（目標2.0以上) = " + DoubleToStr(mPF,2) + "\n";
   strBody = strBody + "含み損 = " + DoubleToStr(latentLoss ,2) + "\n";	   				
   strBody = strBody + "含み益 = " + DoubleToStr(latentProf ,2) + "\n";
   strBody = strBody + "========================" + "\n";					

   //取引対象価格帯の表示
   strBody = strBody + "取引可能価格帯について" + "\n";	
   strBody = strBody + "対象通貨                  =>" + global_Symbol + "<\n";	
   strBody = strBody + "メール送信時のASK            =>" + DoubleToStr(MarketInfo(global_Symbol,MODE_ASK) ,global_Digits ) + "<\n";	
   strBody = strBody + "メール送信時のBID            =>" + DoubleToStr(MarketInfo(global_Symbol,MODE_BID) ,global_Digits) + "<\n";
   strBody = strBody + "過去の最大値（past_max）      =>" + DoubleToStr(past_max ,global_Digits) + "<(" + TimeToStr(past_maxTime) + ")" +  "\n";	
   strBody = strBody + "ショート取引上限値（mShort_Max） =>" + DoubleToStr(mShort_Max ,global_Digits) + "<\n";	
   strBody = strBody + "ショート取引下限値（mShort_Min） =>" + DoubleToStr(mShort_Min ,global_Digits) + "<\n";	
   strBody = strBody + "ロング取引上限値（mLong_Max）   =>" + DoubleToStr(mLong_Max ,global_Digits) + "<\n";	
   strBody = strBody + "ロング取引下限値（mLong_Min）   =>" + DoubleToStr(mLong_Min ,global_Digits) + "<\n";	
   strBody = strBody + "過去の最小値（past_min）      =>" + DoubleToStr(past_min ,global_Digits) + "<(" + TimeToStr(past_minTime) + ")" + "\n";	
   strBody = strBody + "========================" + "\n";		

   //取引可能価格一覧の表示
   strBody = strBody + "取引可能価格一覧" + "\n";	
   strBody = strBody + getNearTradablePriceList(global_Symbol);
   strBody = strBody + "========================" + "\n";		

   
   //メールを送信する。
   SendMail(strSubject , strBody);
   //mMailFlag = false;
}
 	

//+------------------------------------------------------------------+
//|   外部パラメーターに不適切な値が設定されていれば、falseを返す                                              |
//+------------------------------------------------------------------+

bool checkExternalParam() {
   if(PAST_SPAN < 0) {
      printf( "[%d]エラー PAST_SPAN:%sは、0以上にしてください。" , __LINE__ , IntegerToString(PAST_SPAN));
      return false;
   }      
   if(PAST_LEN <= 0) {
      printf( "[%d]エラー PAST_LEN:%sは、0より大きくしてください。" , __LINE__ , IntegerToString(PAST_SPAN));
      return false;
   }  
   if(ENTRY_WIDTH_PIPS <= 0.0) {
      printf( "[%d]エラー ENTRY_WIDTH_PIPS:%sは、0より大きくしてください。" , __LINE__ , DoubleToStr(ENTRY_WIDTH_PIPS));
      return false;
   }      


//past_width = past_max - past_min
//past_max  -----------------------------------------------------
//             ↓      EXCLUDE_MAX_PER （取引不能）
//mShort_Max-----------------------------------------------------
//             → SHORT_ENTRY_WIDTH_PER (ショート実行可能)
//mShort_Min-----------------------------------------------------
//　　　　　　　　　　　取引不能
//                
//mLong_Max -----------------------------------------------------
//             → LONG_ENTRY_WIDTH_PER (ロング実行可能)
//mLomg_Min-----------------------------------------------------
//             ↑      EXCLUDE_LOWER_PER（取引不能）
//past_min  -----------------------------------------------------
   if(SHORT_ENTRY_WIDTH_PER < 0 || SHORT_ENTRY_WIDTH_PER >= 100) {
      printf( "[%d]エラー SHORT_ENTRY_WIDTH_PER:%sは、0以上100未満にしてください。" , __LINE__ , DoubleToStr(SHORT_ENTRY_WIDTH_PER));
      return false;
   }      
   if(LONG_ENTRY_WIDTH_PER < 0 || LONG_ENTRY_WIDTH_PER >= 100) {
      printf( "[%d]エラー LONG_ENTRY_WIDTH_PER:%sは、0以上100未満にしてください。" , __LINE__ , DoubleToStr(LONG_ENTRY_WIDTH_PER));
      return false;
   }
   if(EXCLUDE_ENTRY_PER < 0 || EXCLUDE_ENTRY_PER >= 100) {
      printf( "[%d]エラー EXCLUDE_ENTRY_PER:%sは、0以上100以下にしてください。" , __LINE__ , DoubleToStr(EXCLUDE_ENTRY_PER));
      return false;
   }

   if(LONG_ENTRY_WIDTH_PER + SHORT_ENTRY_WIDTH_PER > 100 ||
      LONG_ENTRY_WIDTH_PER + SHORT_ENTRY_WIDTH_PER <= 0 ) {
      printf( "[%d]エラー LONG_ENTRY_WIDTH_PER:%sとSHORT_ENTRY_WIDTH_PERの合計は100以下にしてください。" , __LINE__ , DoubleToStr(LONG_ENTRY_WIDTH_PER), DoubleToStr(SHORT_ENTRY_WIDTH_PER));
      return false;
   }  
   if(EXCLUDE_ENTRY_PER >= LONG_ENTRY_WIDTH_PER||
      EXCLUDE_ENTRY_PER >= SHORT_ENTRY_WIDTH_PER ) {
      printf( "[%d]エラー EXCLUDE_ENTRY_PER:%は、LONG_ENTRY_WIDTH_PER:%s及びSHORT_ENTRY_WIDTH_PE両方より小さくしてください。" , __LINE__ , DoubleToStr(LONG_ENTRY_WIDTH_PER), DoubleToStr(SHORT_ENTRY_WIDTH_PER));
      return false;
   }
   return true;
}


//+------------------------------------------------------------------+
//|   グローバル変数の初期値に不適切な値が設定されていれば、falseを返す                                              |
//+------------------------------------------------------------------+
bool checkGlobalParam() {
   if(StringLen(global_Symbol) <= 0) {
      printf( "[%d]エラー 通貨ペア名の取得に失敗しました。" , __LINE__ );
      return false;
   }
   if(global_Digits <= 0) {
      printf( "[%d]エラー 単位の取得に失敗しました。" , __LINE__ );
      return false;
   }
   if(global_Points <= 0) {
      printf( "[%d]エラー 桁数の取得に失敗しました。" , __LINE__ );
      return false;
   }
   if(global_LotSize <= 0) {
      printf( "[%d]エラー 単位ロット数の取得に失敗しました。" , __LINE__ );
      return false;
   }
   if(global_StopLevel < 0) {
      printf( "[%d]エラー ストップレベルの取得に失敗しました。" , __LINE__ );
      return false;
   }
   return true;
}


//+------------------------------------------------------------------+
//| DBに接続する。                                                   |
//| 接続に失敗した時、falseを返す。                                  |
//+------------------------------------------------------------------+
bool DB_initial_Connect2DB() {
   // C:\Program Files (x86)\FXTF MT4_20201001\MQL4\scripts
   INI = TerminalInfoString(TERMINAL_PATH)+"\\MQL4\\Scripts\\MyConnection.ini";
 
   // INIファイルから、DB接続情報を取得する。
   Host = ReadIni(INI, "MYSQL", "Host");
   User = ReadIni(INI, "MYSQL", "User");
   Password = ReadIni(INI, "MYSQL", "Password");
   Database = ReadIni(INI, "MYSQL", "Database");
   Port     = (int)StringToInteger(ReadIni(INI, "MYSQL", "Port"));
   Socket   = ReadIni(INI, "MYSQL", "Socket");
   ClientFlag = CLIENT_MULTI_STATEMENTS;
 
   // DBに接続する。
   DB = MySqlConnect(Host, User, Password, Database, Port, Socket, ClientFlag);
   if(DB == -1) {
      printf( "[%d]エラー　DB接続失敗:%s" , __LINE__, MySqlErrorDescription);
      return false;
   }

   return true;
}






