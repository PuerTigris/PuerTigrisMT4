// 更新日 22020506 08:06

// 20220420 PuellaTigrisST_4から新規作成
//          差額の統計分析を利用するコンセプトは継承しつつ、作り直し。
//          DB接続はしない。


// [MT4プログラミング]小ネタ バックテスト時のiCloseは1000本前までに限定される。
// http://mt4program.blogspot.com/2015/10/mt4-iclose1000.html


/* ＜＜コンセプト＞＞
 ０．差額の定義
 　　https://sci-fx.net/fx-dist-time-dep/ 
　　　値動き：終値 - 始値　←こちらが正規分布。
　　　値幅　：高値 - 安値
　　　差額を、値動き：終値 - 始値とする。

１．発注には、信頼区間を使う。
・シフト1の差額が、信頼区間μ ± n × σの外にあれば、異常な差額が発生したことになる。
・差額が信頼区間外になることはめったにないため、揺り戻しが期待できる。
　- シフト1の差額が正の時は、起こりえない上昇が発生したことから、ショート。
　- 差額が負の時は、起こりえない下落が発生したことから、ロング

２．利確、損切の設定に最頻値（最頻区間の代表値）を使う。
・差額が、最頻値近くにあれば、よくある差額（＝動き）でしかないので、取引は見送り。
・最頻値で動くことが、最も多いのであれば、利確、損切の値に使える。
　- 最頻値が正の時は、
　　ロングの利確値をこの範囲内にすることで、繰り返し利確できる。
　　ショートの損切値をこの範囲外にすることで、損切が発生しづらくなる。
  - 最頻値が負の時は、
　　ロングの損切値をこの範囲外にすることで、損切が発生しづらくなる。
　　ショートの利確値をこの範囲内にすることで、繰り返し利確できる。


*/

//+------------------------------------------------------------------+	
//| PuellaTigrisST2                                        　　       |	
//|  Copyright (c) 2016 トラの親 All rights reserved.                |	
//|                                                                  |
//+------------------------------------------------------------------+	
#property copyright "Copyright (c) 2016 トラの親 All rights reserved."				
#property link      "http://nenshuuha.blog.fc2.com/"						
// #property strict
//+------------------------------------------------------------------+	
//| ヘッダーファイル読込                                             |	
//+------------------------------------------------------------------+	
#include <Tigris_COMMON.mqh>
#include <Tigris_Statistics.mqh>
 

 	
	
//+------------------------------------------------------------------+	
//| 定数宣言　                                                       |	
//+------------------------------------------------------------------+	
#define MAX_PRICE_NUM  1000  // 価格データ数最大値
//#define MAX_POP_NUM    1000  // 分析する集合の母数最大値
//#define MIN_POP_NUM    3     // 分析する集合の母数最小値

// 差額の計算方法を定数化
#define CLOSE_MINUS_OPEN 1 // 値動き：終値 - 始値　←こちらが正規分布。
#define HIGH_MINUS_LOW   2 //　値幅　：高値 - 安値

//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
extern int POP_NUM   = 100; //母集団の数。実行時点から何本前の足までを統計分析の対象とするか。
// 2015年10月27日火曜日[MT4プログラミング]小ネタ バックテスト時のiCloseは1000本前までに限定される。
// http://mt4program.blogspot.com/2015/10/mt4-iclose1000.html
extern int    ST2_PRICEDIFF_METHOD = CLOSE_MINUS_OPEN; // 1か2。差額の計算方法。1:値動き：終値 - 始値、2:値幅　：高値 - 安値
extern int    ST2_PRICEDIFF_TF     = 0;      // 0から9。差額の計算に使う時間軸
extern int    ST2_PRICEDIFF_SHIFT  = 1;      // 0か1。0:現在のBIDかASK - シフト０の始値, 1:シフト１の終値 - シフト１の始値
extern int    ST2_CLASS_NUM        = 20;     // 最頻値（区間）を計算するため、母数の最大値と最小値を等分する数。
extern double ST2_SIGMA            = 3.0;    // μ ± n × σnのn

extern int    MagicNumberST2       = 202204123;


extern bool   testAdditionalCond = false;
//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
//int g_PriceDiff_Method = CLOSE_MINUS_OPEN;  // CLOSE_MINUS_OPEN, HIGH_MINUS_LOW
datetime ST2time0 = 0;
datetime execST2time = 0;
st_Pricedata g_last_st_PricedataArray[MAX_PRICE_NUM];  // 価格の再取得を省略するために使う。
                           
//+------------------------------------------------------------------+	
//| 初期処理                                                         |	
//+------------------------------------------------------------------+	
int init()	
{
   updateExternalParamCOMM();

   if(checkExternalParamCOMMON() != true) {
      printf( "[%d]ST2エラー 外部パラメーターに不適切な値あり" , __LINE__);
      return INIT_SUCCEEDED;
   }
   if(checkExternalParam() != true) {
      printf( "[%d]ST2エラー 外部パラメーターに不適切な値あり" , __LINE__);
      return INIT_SUCCEEDED;
   }
   if(checkGlobalParam() != true) {
      printf( "[%d]ST2エラー 大域変数に不適切な値あり" , __LINE__);
      return INIT_SUCCEEDED;
   }
   
   return(0);	
}	
	
//+------------------------------------------------------------------+	
//| 終了処理                                                         |	
//+------------------------------------------------------------------+	
int deinit()	
{	

   return(0);	
}	
	
//+------------------------------------------------------------------+	
//| メイン処理                                                       |	
//+------------------------------------------------------------------+	
int start()   {
   if(TimeCurrent() - execST2time >= UpdateMinutes * 60) {
      ST2_Main(global_Symbol);

      // ２．全オーダーの利確値、損切値の再設定を行う。
      // ST2専用の指値と逆指値をセットする。
      doForcedSettlement_ST2(MagicNumberST2, global_Symbol);
      
      // TP_PIPSかSL_PIPSのどちらかが0より大きければ、全オーダーの指値と逆指値をセットする。	
      if(TP_PIPS > 0 || SL_PIPS > 0) {		
         update_AllOrdersTPSL(global_Symbol, MagicNumberST2, TP_PIPS, SL_PIPS);
      } 
   
      // ３．FLOORING設定をする。
      // 最小利食値FLOORINGが設定されていれば、損切値の更新を試す。
      if(FLOORING >= 0) {
         flooringSL(global_Symbol, MagicNumberST2, FLOORING, FLOORING_CONTINUE);
      }
   
      // ４．強制決済をする。
      // TP_PIPSかSL_PIPSのどちらかが0より大きければ、マジックナンバーをキーとして強制決済をする。	
      if(TP_PIPS > 0 || SL_PIPS > 0) {		
         doForcedSettlement(MagicNumberST2, global_Symbol, TP_PIPS, SL_PIPS);
      } 
   }   

   return(0);
}

//+------------------------------------------------------------------+
//|   even_intervals()                                               |
//+------------------------------------------------------------------+  

int ST2_Main(string mSymbol) {

   bool   open_flag = false;
   bool   exist_flag = false;
   double tp = 0.0;
   int    orderNum = 0;
   double mMarketinfoMODE_ASK = MarketInfo(mSymbol,MODE_ASK);
   double mMarketinfoMODE_BID = MarketInfo(mSymbol,MODE_BID);
 
   double mMarketinfoMODE_POINT = global_Points;
   int    mIndex = 0;
   
   bool   flgUpdate_past_maxmin = false; // past_max, past_minが更新されればtrueにする。
   double bufNewMaxMin = DOUBLE_VALUE_MIN;
   
   ST2_PRICEDIFF_TF = getTimeFrame(ST2_PRICEDIFF_TF);
   if(ST2_PRICEDIFF_TF == 0) {
      ST2_PRICEDIFF_TF = Period();
   }

   // 当初、残高不足かどうかは、発注直前に判断していた。
   // 処理肥大化に伴い、簡略化のため、先頭のこの位置に移した。
   bool mSellable = checkMargin(mSymbol, OP_SELL, LOTS, LIMMITMARGINLEVEL);
   bool mBuyable  = checkMargin(mSymbol, OP_BUY,  LOTS, LIMMITMARGINLEVEL);

   //
   //ロング、ショートの可否を
   //①取引可能な価格帯か
   //②価格帯を等分した時のいずれかの境界値に近いか
   //という視点で判断する。
   double   mPast_max     = DOUBLE_VALUE_MIN; //過去の最高値
   datetime mPast_maxTime = -1;               //過去の最高値の時間
   double   mPast_min     = DOUBLE_VALUE_MIN; //過去の最安値
   datetime mPast_minTime = -1;               //過去の最安値の時間
   double   mPast_width   = DOUBLE_VALUE_MIN; // 過去値幅。past_max - past_min
   double   mLong_Min     = DOUBLE_VALUE_MIN; // ロング取引を許可する最小値
   double   mLong_Max     = DOUBLE_VALUE_MIN; // ロング取引を許可する最大値
   double   mShort_Min    = DOUBLE_VALUE_MIN; // ショート取引を許可する最小値
   double   mShort_Max    = DOUBLE_VALUE_MIN; // ショート取引を許可する最大値   
   bool flag_get_TradingLines = false;
   flag_get_TradingLines = 
      get_TradingLines(mSymbol,       //　通貨ペア
                       TIME_FRAME_MAXMIN,// 計算に使う時間軸
                       SHIFT_SIZE_MAXMIN,     // 計算対象にするシフト数
                       mPast_max,     //過去の最高値
                       mPast_maxTime, //過去の最高値の時間
                       mPast_min,     //過去の最安値
                       mPast_minTime, //過去の最安値の時間
                       mPast_width,   // 過去値幅。past_max - past_min
                       mLong_Min,     // ロング取引を許可する最小値
                       mLong_Max,     // ロング取引を許可する最大値
                       mShort_Min,    // ショート取引を許可する最小値
                       mShort_Max     // ショート取引を許可する最大値                       
                      );
   if(flag_get_TradingLines == false) {
printf( "[%d]ST2MAINエラー 取引ラインの取得失敗" , __LINE__);                      
   
      return -1;
   }
   
   //ロングのオープン手順
   //①ASKが、mLong_Max　～　mLong_Minの間であること。
   //②ASKが、過去最高値と過去最安値をエントリー間隔ENTRY_WIDTH_PIPSで分割した時のいずれかの境界値に近いこと。
   //③スプレッドASK-BIDが、MAX_SPREAD_POINT未満であること。
   
   //過去最高値と過去最安値をエントリー間隔ENTRY_WIDTH_PIPSで分割した時の直近の境界値
   double nearTradablePrice = getNearTradablePrice(mSymbol, mMarketinfoMODE_ASK, mPast_max, mPast_min);
   double adjustValue       = global_Points;
   int EntrywithTech_signal = NO_SIGNAL;

   double mTP_POINT = DOUBLE_VALUE_MIN; // 利確値を計算するためのポイント数
   double mSL_POINT = DOUBLE_VALUE_MIN; // 損切値を計算するためのポイント数 
   double mTP_Price = 0.0; // 発注時に設定する利確値
   double mSL_Price = 0.0; // 発注時に設定する損切値

/*printf( "[%d]ST2MAIN mLong_Max=%s mLong_Min=%s ASK=%s  nearTradablePrice=%s" , __LINE__,
      DoubleToStr(mLong_Max, global_Digits),
      DoubleToStr(mLong_Min, global_Digits),
      DoubleToStr(mMarketinfoMODE_ASK, global_Digits),      
      DoubleToStr(nearTradablePrice, global_Digits)
   );*/
   int ticket_num = -1; 
   string bufComment = "";    // <TP=%s><SL=%s>をコメントに追加する
   if(ST2time0 != Time[0]     // 連続取引の制限
      && (mBuyable == true )  // 買い増し可能な残高かどうか。
      && (mLong_Min > 0.0 && mLong_Max > 0.0 && NormalizeDouble(mLong_Max, global_Digits) > NormalizeDouble(mLong_Min, global_Digits))   // 取引可能価格帯の上限と下限が意味のある値であること
      && (NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) > NormalizeDouble(mLong_Min, global_Digits) && NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) < NormalizeDouble(mLong_Max, global_Digits))  //①ASKが範囲内にあること
      && (nearTradablePrice > 0.0 && 
       MathAbs(NormalizeDouble(nearTradablePrice, global_Digits) - NormalizeDouble(mMarketinfoMODE_ASK, global_Digits)) / adjustValue < NormalizeDouble(ENTRY_WIDTH_PIPS / DISTANCE, global_Digits) )
       //②直近の取引可能価格とのずれがENTRY_WIDTH_PIPS（エントリーする間隔。PIPS数。）の半分未満であること
    ) {  
    
      // オープンフラグopen_flagをfalseに初期設定する。
      open_flag  = false;
      exist_flag = false;
      // 関数find_Same_Entry(magic, OP_BUY, ASK)を使ってオープン中の取引を探し、
      // 同じOP_BUYの取引が存在しなければロングをオープンする。→　オープンフラグopen_flag = true
      exist_flag = find_Same_Entry(MagicNumberST2, mSymbol, OP_BUY, mMarketinfoMODE_ASK);

      if(exist_flag == false) {
         open_flag = true;
      }
      else {
         open_flag = false;
      }      
      // EntrywithTech_signal, ticket_numを初期化する。
      EntrywithTech_signal = NO_SIGNAL;
      ticket_num           = -1;      
      
      // 同じような位置に取引がない（open_flagがtrue）のであれば、ロング取引を準備する。
      if(open_flag == true) {
         // 価格帯以外の条件で、売買シグナルを確認する。
         EntrywithTech_signal = tradeST(mSymbol,
                                        mTP_POINT,  
                                        mSL_POINT);
         if(EntrywithTech_signal == BUY_SIGNAL) {
            //if(ST2time0 != Time[0] && mBuyable == true) {
//            if(ST2time0 != Time[0]) {
               // 発注前の利確値又は損切値の計算
               if(mTP_POINT < DOUBLE_VALUE_MIN && mSL_POINT < DOUBLE_VALUE_MIN) {
                  mTP_POINT = 0.0;
                  mSL_POINT = 0.0;
               }

               // 利確値、損切値を計算する。
               if(mTP_POINT > DOUBLE_VALUE_MIN) {
                  mTP_Price = mMarketinfoMODE_ASK + mTP_POINT * global_Points;
               }
               if(mSL_POINT > DOUBLE_VALUE_MIN) {
                  // 20220426 最頻値を使って損切値設定すると、直ぐに損切にあう。→　n×σが入ったmSL_POINTを使って発注する。
                  mSL_Price = mMarketinfoMODE_ASK - mSL_POINT * global_Points;
               }
               
               if(mSL_Price < 0.0) {
                  mSL_Price = 0.0;
               }
               if(mTP_Price < 0.0) {
                  mTP_Price = 0.0;
               }
               bufComment = g_StratName95 + "<TP=" + DoubleToStr(mTP_Price, global_Digits) + "><SL=" + DoubleToStr(mSL_Price, global_Digits) + ">";
printf( "[%d]ST2テスト　買い発注時のmTP_POINT=%s   mSL_POINT%s" , __LINE__,
         DoubleToStr(mTP_POINT, global_Digits),
         DoubleToStr(mSL_POINT, global_Digits)
         );
printf( "[%d]ST2テスト　mOrderSend4のコメント=%s" , __LINE__,bufComment);
               ticket_num = mOrderSend4(mSymbol,OP_BUY,LOTS,mMarketinfoMODE_ASK,SLIPPAGE,mSL_Price,mTP_Price,bufComment,MagicNumberST2,0,LINE_COLOR_LONG);
               if( ticket_num > 0) { 
                  ST2time0 = Time[0];
               }
               else {
                  printf( "[%d]ST2エラー 買い発注の失敗:：%s" , __LINE__ , GetLastError());
               }
//            }
         }
      }
   }


   //ショートのオープン手順
   //①BIDが、mShort_Max　～　mShort_Minの間であること。
   //②BIDが、過去最高値と過去最安値をエントリー間隔ENTRY_WIDTH_PIPSで分割した時のいずれかの境界値に近いこと。
   //③スプレッドASK-BIDが、MAX_SPREAD_POINT未満であること。

   //過去最高値と過去最安値をエントリー間隔ENTRY_WIDTH_PIPSで分割した時の直近の境界値
   nearTradablePrice = getNearTradablePrice(mSymbol, mMarketinfoMODE_BID, mPast_max, mPast_min);

   if(ST2time0 != Time[0]       // 連続取引の制限
      && (mSellable == true )   // 売り増し可能な残高かどうか。
      && (mShort_Min > 0.0 && mShort_Max > 0.0 && NormalizeDouble(mShort_Max, global_Digits) > NormalizeDouble(mShort_Min, global_Digits))  // 取引可能価格帯の上限と下限が意味のある値であること
      && (NormalizeDouble(mMarketinfoMODE_BID, global_Digits) > NormalizeDouble(mShort_Min, global_Digits) && NormalizeDouble(mMarketinfoMODE_BID, global_Digits) < NormalizeDouble(mShort_Max, global_Digits))   //①BIDが範囲内にあること
      && (nearTradablePrice > 0.0 && MathAbs(NormalizeDouble(nearTradablePrice, global_Digits) - NormalizeDouble(mMarketinfoMODE_BID, global_Digits)) / adjustValue < NormalizeDouble(ENTRY_WIDTH_PIPS / DISTANCE, global_Digits) )
             ) {  
      // オープンフラグopen_flagをfalseに初期設定する。
      open_flag = false;
      exist_flag = false;
    // 関数find_Same_Entry(magic, OP_SELL, BID)を使ってオープン中の取引を探し、
    // 同じOP_SELLの取引が存在しなければロングをオープンする。→　オープンフラグopen_flag = true
      exist_flag = find_Same_Entry(MagicNumberST2, mSymbol, OP_SELL, mMarketinfoMODE_BID);
      if(exist_flag == false) {
         open_flag = true;
      }
      else {
         open_flag = false;
      }      
      
      // EntrywithTech_signal, ticket_numを初期化する。
      EntrywithTech_signal = NO_SIGNAL;
      ticket_num           = -1;      

      // 同じような位置に取引がない（open_flagがtrue）のであれば、ショート取引を準備する。
      if(open_flag == true) {
         // 価格帯以外の条件で、売買シグナルを計算する
         EntrywithTech_signal = tradeST(mSymbol,
                                        mTP_POINT,  
                                        mSL_POINT);
         if(EntrywithTech_signal == SELL_SIGNAL) {
//            if(ST2time0 != Time[0]) {
               // 利確値又は損切値の計算
            if(mTP_POINT < DOUBLE_VALUE_MIN && mSL_POINT < DOUBLE_VALUE_MIN) {
               mTP_POINT = 0.0;
               mSL_POINT = 0.0;
            }
               // 利確値、損切値を計算する。
               if(mTP_POINT > DOUBLE_VALUE_MIN) {
                  mTP_Price = mMarketinfoMODE_BID - mTP_POINT * global_Points;
               }
               if(mSL_POINT > DOUBLE_VALUE_MIN) {
                  // 20220426 最頻値を使って損切値設定すると、直ぐに損切にあう。→　n×σが入ったmSL_POINTを使って発注する。
                  mSL_Price = mMarketinfoMODE_BID + mSL_POINT * global_Points;
               }
               if(mSL_Price < 0.0) {
                  mSL_Price = 0.0;
               }
               if(mTP_Price < 0.0) {
                  mTP_Price = 0.0;
               }
               bufComment = g_StratName95 + "<TP=" + DoubleToStr(mTP_Price, global_Digits) + "><SL=" + DoubleToStr(mSL_Price, global_Digits) + ">";
//printf( "[%d]ST2テスト　mOrderSend4のコメント=%s" , __LINE__,bufComment);
               
               ticket_num = mOrderSend4(mSymbol,OP_SELL,LOTS,mMarketinfoMODE_BID,SLIPPAGE,mSL_Price,mTP_Price,bufComment,MagicNumberST2,0,LINE_COLOR_SHORT);
               if(ticket_num > 0) { 
                  ST2time0 = Time[0];

/*printf( "[%d]ST2テスト　チケット番号=%d 売り発注時の利確=%s  損切=%s" , __LINE__,
             ticket_num,
             DoubleToStr(mTP_Price, global_Digits),
             DoubleToStr(mSL_Price, global_Digits)  );*/

 
               }
               else {
                  printf( "[%d]ST2エラー 売り発注の失敗:：%s" , __LINE__ , GetLastError());
               }
//            }
         }
      }
   }
   return 0;//正常終了
}

//
// 値動き、値幅を使った取引 
// 返り値は、BUY＿SIGNAL, SELL_SIGNAL, NO_SIGNAL
// 引数で、利確、損切用のポイント数を返す。
// 
int tradeST(string mSymbol,     // 通貨ペア
             double &mTP_POINT,  // 出力：利確値を設定する時のポイント数
             double &mSL_POINT   // 出力：損切値を設定する時のポイント数
) {
   int bufTrend = NoTrend;

   int upTrend_Num   = 0;
   int downTrend_Num = 0;
   int noTrend_Num   = 0;

   // １．judgeBuySell_STにより、売買シグナル、利確値、損切値を取得して、発注する。
   int    flagBuySell = 
   judgeBuySell_ST(mSymbol,         // 通貨ペア
                   ST2_PRICEDIFF_TF,// 時間軸 
                   mTP_POINT,       // 出力：最頻値を使って求めた発注する際の利確ポイント
                   mSL_POINT        // 出力：最頻値を使って求めた発注する際の損切ポイント
                    ) ;
   if(flagBuySell == BUY_SIGNAL) {
printf( "[%d]ST2　買いシグナル　mTP_POINT=>%s<  mSL_POINT=>%s<" , __LINE__,
               DoubleToStr(mTP_POINT, global_Digits),
               DoubleToStr(mSL_POINT, global_Digits)
            );

      if(testAdditionalCond == true) {
         get_Trend_Combo(mSymbol,      // 通貨ペア 
                         Period(),     // 時間軸
                         1,            // シフト
                         upTrend_Num,  // 出力：UpTrend上昇傾向にあると判断した数
                         downTrend_Num,// 出力：DownTrend下落傾向にあると判断した数
                         noTrend_Num   // 出力：NoTrend傾向無し判断した数
                         );
         if(downTrend_Num > upTrend_Num) {  // 下落傾向が強ければ買いシグナルを取消
            flagBuySell = NO_SIGNAL;
         }
      }

   }
   else if(flagBuySell == SELL_SIGNAL) {
printf( "[%d]ST2　売りシグナル　mTP_POINT=>%s<  mSL_POINT=>%s<" , __LINE__,
               DoubleToStr(mTP_POINT, global_Digits),
               DoubleToStr(mSL_POINT, global_Digits)
            );

      if(testAdditionalCond == true) {
         get_Trend_Combo(mSymbol,      // 通貨ペア 
                         Period(),     // 時間軸
                         1,            // シフト
                         upTrend_Num,  // 出力：UpTrend上昇傾向にあると判断した数
                         downTrend_Num,// 出力：DownTrend下落傾向にあると判断した数
                         noTrend_Num   // 出力：NoTrend傾向無し判断した数
                         );
         if(downTrend_Num < upTrend_Num) {  // 上昇傾向が強ければ売りシグナルを取消
            flagBuySell = NO_SIGNAL;
         }
      }

   }
   else  {
      flagBuySell = NO_SIGNAL;            
   }   

   return flagBuySell;
}


// 
// 売買フラグを返す。
//
int judgeBuySell_ST(string mSymbol,     // 通貨ペア
                    int    mTimeframe,  // 時間軸 
                    double &mTP_POINT,  // 出力：発注する際の利確値に使うポイント数を返す。設定不要時は、DOUBLE_VALUE_MIN
                    double &mSL_POINT   // 出力：発注する際の損切値に使うポイント数を返す。設定不要時は、DOUBLE_VALUE_MIN
                    ) {
   st_Pricedata m_st_PricedataArray[MAX_PRICE_NUM];  // 価格を格納する配列
   double mSL_POINT_cand = DOUBLE_VALUE_MIN;  // 損切候補価格
   mTP_POINT = DOUBLE_VALUE_MIN;
   mSL_POINT = DOUBLE_VALUE_MIN;
//   init_st_PricedataArray(m_st_PricedataArray, MAX_PRICE_NUM);  // 配列の初期化
   int flagBuySell = NO_SIGNAL;

   // １．シフト１からPOP_NUMまでの価格を配列st_PricedataArrayに読み込む
   bool flag_get_st_Pricedata = 
        get_st_Pricedata(mSymbol,    // 価格を取得する時の通貨ペア
                         mTimeframe, // 時間軸
                         Time[0],    // 基準時刻
                         POP_NUM,    // 取得するデータ数
                         m_st_PricedataArray // 出力：取得結果を格納した配列
                      
                        );
   if(flag_get_st_Pricedata == false) {
      printf( "[%d]ST2　価格データを取得失敗" , __LINE__);
      return NO_SIGNAL;
   }
   
   // ２．差額（値動き：終値 - 始値）の平均と偏差、最頻値を計算する。
   double   diffArray[MAX_PRICE_NUM];
   ArrayInitialize(diffArray, DOUBLE_VALUE_MIN);
   double   priceDiff_Mean  = DOUBLE_VALUE_MIN;
   double   priceDiff_Sigma = DOUBLE_VALUE_MIN; 
//   double   priceMean       = DOUBLE_VALUE_MIN;
//   double   priceSigma      = DOUBLE_VALUE_MIN; 

   st_class priceDiff_Mode[MAX_PRICE_NUM];
   init_st_class(priceDiff_Mode);

   bool flag_get_priceDiff_Mean_Sigma_Mode = 
   get_priceDiff_Mean_Sigma_Mode(m_st_PricedataArray, // 価格データを格納した配列
                            ST2_PRICEDIFF_METHOD,// 差額の計算方法
                            diffArray,           // 出力：構造体配列。平均と偏差の計算対象となった差額（ポイント換算）
                            priceDiff_Mean,      // 出力：平均の計算結果
                            priceDiff_Sigma,     // 出力：偏差の計算結果
                            priceDiff_Mode       // 出力：構造体配列。最頻値の計算結果
                            );
   if(flag_get_priceDiff_Mean_Sigma_Mode == false) {
      printf( "[%d]ST2　価格データを平均と偏差、最頻値の計算失敗" , __LINE__);
      return NO_SIGNAL;
   }

   // 直近の差額を計算する。※差額は、、シフト１の終値 - シフト１の始値、　現在のBIDかASK - シフト０の始値のパターンを想定する。
   double last_priceDiff =  
      get_last_priceDiff(ST2_PRICEDIFF_METHOD,    // 差額の計算方法
                         ST2_PRICEDIFF_SHIFT);    // 0:現在のBIDかASK - シフト０の始値, 1:シフト１の終値 - シフト１の始値                      
   if(last_priceDiff <= DOUBLE_VALUE_MIN) {
      printf( "[%d]ST2　直近の差額の計算失敗　時刻%s  【参考】平均=%s  偏差=%s" , __LINE__,
         TimeToStr(Time[0]),
         DoubleToStr(priceDiff_Mean, global_Digits),
         DoubleToStr(priceDiff_Sigma, global_Digits)         
      );
      return NO_SIGNAL;
   }
                    

   //３．差額（※）が信頼区間μ ± n × σの外かを判断する。
   // judgeIncludeは、引数last_priceDiffが、priceDiff_Mean±mConst * priceDiff_Sigmaの範囲内にあれば、trueを返す。
   bool flag_judgeInclude = 
   judgeInclude(priceDiff_Mean, priceDiff_Sigma, ST2_SIGMA, last_priceDiff, "ST2");


   // ４．差額が信頼区間外の時、売買シグナルを返す。
   // - 差額が正の時（＝統計的にあり得ない上昇をした）、ショート
   // - 差額が負の時（＝統計的にあり得ない下落をした）、ロング
   // なお、売買シグナルがロング、ショートいずれかの時は、1つ上の時間軸のトレンドを加味するパターンを用意する。
   if(flag_judgeInclude == false) {  // judgeIncludeは、範囲内にあればtrueのため、範囲外にある時の条件はfalse
/*      printf( "[%d]ST2　mMean±mConst%s*mSigmaの範囲外  平均=%s  偏差=%s　　直近の差額=%s" , __LINE__,
         TimeToStr(Time[0]),
         DoubleToStr(ST2_SIGMA, global_Digits),
         DoubleToStr(priceDiff_Mean, global_Digits),
         DoubleToStr(priceDiff_Sigma, global_Digits),
         DoubleToStr(last_priceDiff, global_Digits)         
      );*/

   
      if(last_priceDiff > 0.0) {
         flagBuySell = SELL_SIGNAL;
      }
      else if(last_priceDiff < 0.0) {
         flagBuySell = BUY_SIGNAL;
      }
      else {
         flagBuySell = NO_SIGNAL;
      }
   }
   else {
      // 何もしない
   }

   /* 利確、損切の設定に最頻値（最頻区間の代表値）を使う。
      ・差額(直近は、last_priceDiff）が、最頻値近くにあれば、よくある差額（＝動き）でしかないので、取引は見送り。
      ・最頻値で動くことが、最も多いのであれば、利確、損切の値に使える。
        - 最頻値が正の時は、
　 　        ロングの利確値をこの範囲内にすることで、繰り返し利確できる。
　　         ショートの損切値をこの範囲外にすることで、損切が発生しづらくなる。
        - 最頻値が負の時は、
　　         ロングの損切値をこの範囲外にすることで、損切が発生しづらくなる。
         　　ショートの利確値をこの範囲内にすることで、繰り返し利確できる。
        → 20220426見直し：発注時には、最頻値を使った利確値を設定する。
                       最頻値を使った損切値は、頻繁な損切を避けるため、それ以上の値で損切をするという意味であり、
                       発注時に使えない。
　　　　　　　　　　　　　         →　発注時の損切値設定は理由が見つかるまで見送る。
   */
   if(flagBuySell == NO_SIGNAL) {
      mTP_POINT = DOUBLE_VALUE_MIN;
      mSL_POINT = DOUBLE_VALUE_MIN;
   }
   else {
      double nearToMeanMode = DOUBLE_VALUE_MIN; 
      if(flagBuySell == BUY_SIGNAL || flagBuySell == SELL_SIGNAL) {
         // 平均値に最も近い最頻値の代表値を返す。
         bool flag_get_NearToMeanMode =
         get_NearToMeanMode(priceDiff_Mode, // 最頻値のフラグが入った構造体
                            priceDiff_Mean, // 平均値。この値に最も近い最頻値を探す。
                            nearToMeanMode  // 出力：最頻値の代表値
                            );
         if(flag_get_NearToMeanMode == false) {
            flagBuySell = NO_SIGNAL;
         }
      }

      if(flagBuySell == BUY_SIGNAL) {
         // 最頻値nearToMeanModeが正であれば、ロングの利確値用ポイント数は、最頻値。
         if(nearToMeanMode >= 0.0) {
            mTP_POINT = nearToMeanMode;
         }
         // 最頻値nearToMeanModeが負であれば、ロングの利確値用ポイントは、DOUBLE_VALUE_MIN。
         else if(nearToMeanMode < 0.0) {
//printf( "[%d]ST2　ロングで最頻値が負のため、mTP_POINTをDOUBLE_VALUE_MINにした" , __LINE__);
         
            mTP_POINT = DOUBLE_VALUE_MIN;
         }
         mSL_POINT = DOUBLE_VALUE_MIN;
      }
      else if(flagBuySell == SELL_SIGNAL) {
         // 最頻値nearToMeanModeが正であれば、ショートの利確値用ポイントは、DOUBLE_VALUE_MIN。
         if(nearToMeanMode >= 0.0) {
            mTP_POINT = DOUBLE_VALUE_MIN;
         }
         // 最頻値nearToMeanModeが負であれば、ショートの利確値用ポイントは、最頻値の絶対値。
         else if(nearToMeanMode < 0.0) {
            mTP_POINT = MathAbs(nearToMeanMode);
         }
         mSL_POINT = DOUBLE_VALUE_MIN;
      }
      else {
         flagBuySell = NO_SIGNAL;
      }
   }
   return flagBuySell;
}

//+------------------------------------------------------------------+
//|   st_PricedataArray配列の初期化                                     |
//+------------------------------------------------------------------+
void init_st_PricedataArray(st_Pricedata &mPricedataArray[], // 出力：初期化対象
                           int                mArraySize // 配列のサイズ
                           ) {
   int i;
   for(i = 0; i < mArraySize; i++) {
      mPricedataArray[i].symbol = "";
      mPricedataArray[i].timeframe = INT_VALUE_MIN;
      mPricedataArray[i].dt        = INT_VALUE_MIN;
      mPricedataArray[i].open      = DOUBLE_VALUE_MIN;
      mPricedataArray[i].high      = DOUBLE_VALUE_MIN;
      mPricedataArray[i].low       = DOUBLE_VALUE_MIN;
      mPricedataArray[i].close     = DOUBLE_VALUE_MIN;
      mPricedataArray[i].volume    = DOUBLE_VALUE_MIN;
   }
}

//+------------------------------------------------------------------+
//|   st_PricedataArray配列が保持する価格データ件数を返す                     |
//+------------------------------------------------------------------+
int howmany_st_Pricedata(st_Pricedata &mPricedataArray[], // 出力：初期化対象
                         int                mArraySize // 配列のサイズ
                        ) {
   int i;
   int count = 0;
   for(i = 0; i < mArraySize; i++) {
      if( 
        (StringLen(mPricedataArray[i].symbol) > 0
         &&
         mPricedataArray[i].timeframe >= 0 
         && 
         mPricedataArray[i].dt     > 0
         && 
         mPricedataArray[i].open   > 0.0
         && 
         mPricedataArray[i].high   > 0.0
         && 
         mPricedataArray[i].low    > 0.0
         && 
         mPricedataArray[i].close  > 0.0
         && 
         mPricedataArray[i].volume >= 0) ) {
         
         count++;
      }
   }
   return count;
}

datetime lastGetPriceDT = 0;
//+------------------------------------------------------------------+
//|   st_PricedataArray配列に価格を代入する。                              |
//+------------------------------------------------------------------+
bool get_st_Pricedata(string   mSymbol,    // 価格を取得する時の通貨ペア
                      int      mTimeframe, // 時間軸
                      datetime mStartDT,          // 基準時刻
                      int      mGetNum,    // 取得するデータ数
                      st_Pricedata &m_st_PricedataArray[] // 出力：取得結果を格納した配列
                     ) {
   int i;
   int j = 0;
                        
if(lastGetPriceDT == mStartDT) {
/*printf( "[%d]ST2　基準時刻に変化がないため、計算省略lastGetPriceDT=%s  >%d=%s<  close=%s" , __LINE__, 
TimeToStr(lastGetPriceDT), mStartDT, TimeToStr(mStartDT));*/

   // グローバル変数からコピーする。
   init_st_PricedataArray(m_st_PricedataArray, MAX_PRICE_NUM);
   for(i = 0; i < ArraySize(m_st_PricedataArray); i++) {
      if(g_last_st_PricedataArray[i].timeframe <= 0){
         break;
      }
      m_st_PricedataArray[i].symbol = g_last_st_PricedataArray[i].symbol;
      m_st_PricedataArray[i].timeframe = g_last_st_PricedataArray[i].timeframe;
      m_st_PricedataArray[i].dt = g_last_st_PricedataArray[i].dt;
      m_st_PricedataArray[i].dtStr = g_last_st_PricedataArray[i].dtStr;
      m_st_PricedataArray[i].open = g_last_st_PricedataArray[i].open;
      m_st_PricedataArray[i].high = g_last_st_PricedataArray[i].high;
      m_st_PricedataArray[i].low = g_last_st_PricedataArray[i].low;
      m_st_PricedataArray[i].close = g_last_st_PricedataArray[i].close;
      m_st_PricedataArray[i].volume = g_last_st_PricedataArray[i].volume;      
   }

   return true;
}


   // 引数の妥当性チェック                  
   if(StringLen(mSymbol) <= 0) {
      printf( "[%d]ST2　通貨ペア名>%s<は不正です。" , __LINE__, mSymbol);
      return false;
   }
   if(mTimeframe < 0) {
      printf( "[%d]ST2　時間軸>%d<は不正です。" , __LINE__, mTimeframe);
      return false;
   }
   if(mTimeframe == PERIOD_CURRENT) {
      mTimeframe = Period();
   }
   if(mGetNum > 1000) {
      printf( "[%d]ST2 %d個の価格データの取得を試みました。最大で1000個です。" , __LINE__, mGetNum);
      return false;
   }               

   int startShift = iBarShift(mSymbol, mTimeframe, mStartDT);
   if(startShift < 0) {
      printf( "[%d]ST2　基準時刻>%d = %s<は不正です。" , __LINE__, mStartDT, TimeToStr(mStartDT));
      return false;
   }
   if(mGetNum < 0) {
      printf( "[%d]ST2　データ取得数>%d<は不正です。" , __LINE__, mGetNum);
      return false;
   }
/*printf( "[%d]ST2　データ取得 mTimeframe>%d<　時刻>%d=%s<" , __LINE__, 
     mTimeframe,
     mStartDT, TimeToStr(mStartDT)
     );*/

   // 配列の初期化
   init_st_PricedataArray(m_st_PricedataArray, MAX_PRICE_NUM);
   init_st_PricedataArray(g_last_st_PricedataArray, MAX_PRICE_NUM); // 同じ基準時刻で価格を再取得するのを防ぐためにコピーを保存する。
   
   j = 0;
   for(i = startShift; i < startShift + mGetNum; i++) {
      m_st_PricedataArray[j].symbol = mSymbol;
      m_st_PricedataArray[j].timeframe = mTimeframe;
      m_st_PricedataArray[j].dt        = mStartDT;
      m_st_PricedataArray[j].dtStr     = TimeToStr(mStartDT);
      m_st_PricedataArray[j].open      = NormalizeDouble(iOpen  (mSymbol, mTimeframe, i), global_Digits);
      m_st_PricedataArray[j].high      = NormalizeDouble(iHigh  (mSymbol, mTimeframe, i), global_Digits);
      m_st_PricedataArray[j].low       = NormalizeDouble(iLow   (mSymbol, mTimeframe, i), global_Digits);
      m_st_PricedataArray[j].close     = NormalizeDouble(iClose (mSymbol, mTimeframe, i), global_Digits);
      m_st_PricedataArray[j].volume    = NormalizeDouble(iVolume(mSymbol, mTimeframe, i), global_Digits);

      g_last_st_PricedataArray[j].symbol    = m_st_PricedataArray[j].symbol;
      g_last_st_PricedataArray[j].timeframe = m_st_PricedataArray[j].timeframe;
      g_last_st_PricedataArray[j].dt = m_st_PricedataArray[j].dt;
      g_last_st_PricedataArray[j].dtStr = m_st_PricedataArray[j].dtStr;
      g_last_st_PricedataArray[j].open = m_st_PricedataArray[j].open;
      g_last_st_PricedataArray[j].high = m_st_PricedataArray[j].high;
      g_last_st_PricedataArray[j].low = m_st_PricedataArray[j].low;
      g_last_st_PricedataArray[j].close = m_st_PricedataArray[j].close;
      g_last_st_PricedataArray[j].volume = m_st_PricedataArray[j].volume;

            
      j++;
      if(j >= MAX_PRICE_NUM) {
         printf( "[%d]ST2　データ取得数がオーバーフローします　処理の開始シフト>%d<　件数>%d<" , __LINE__, startShift, mGetNum);
         break;
      }
   }
   
   lastGetPriceDT = mStartDT;
   return true;
}
                    


//+------------------------------------------------------------------+
//|   全ての差額とその平均、偏差を計算する。                                               |
//+------------------------------------------------------------------+
bool get_priceDiff_Mean_Sigma_Mode(st_Pricedata &m_st_PricedataArray[], // 価格データを格納した配列
//                              int               mDataNum,             // 格納したデータ数
                              int               mPRICEDIFF_METHOD,    // 差額の計算方法
                              double            &mDiffArray[],        // 出力：平均と偏差の計算対象となった差額（ポイント換算）
                              double            &priceDiff_Mean,      // 出力：平均の計算結果
                              double            &priceDiff_Sigma,     // 出力：偏差の計算結果
                              st_class          &m_st_classArray[]    // 出力：階級（最頻値フラグ設定済み）
                            ) {
   
   //
   // １．平均、偏差を計算する。
   // 
   
   
                            
   // 差額をglobal_Pointsで割ってポイント化した値を計算する。                            
   ArrayInitialize(mDiffArray, DOUBLE_VALUE_MIN);
   int i;
   int m_st_PricedataArray_Size = ArraySize(m_st_PricedataArray);
   int mDataNum = 0;
/*
for(i = 0; i < m_st_PricedataArray_Size; i++) {
if(m_st_PricedataArray[i].dt <= 0) {
break;
}
printf( "[%d]ST2 m_st_PricedataArray[%d] m_st_PricedataArray_Size=%d  close=%s open=%s high=%s low=%s" , __LINE__,
          i,m_st_PricedataArray_Size,
          DoubleToStr(m_st_PricedataArray[i].close, global_Digits),
          DoubleToStr(m_st_PricedataArray[i].open, global_Digits),
          DoubleToStr(m_st_PricedataArray[i].high, global_Digits),          
          DoubleToStr(m_st_PricedataArray[i].low, global_Digits));                   
}
*/
   
   for(i = 0; i < m_st_PricedataArray_Size; i++) {
      if(m_st_PricedataArray[i].dt <= 0) {
         break;
      }
      double buf = 0.0;
      if(mPRICEDIFF_METHOD == CLOSE_MINUS_OPEN) {
         buf = NormalizeDouble(m_st_PricedataArray[i].close, global_Digits) - NormalizeDouble(m_st_PricedataArray[i].open, global_Digits);
      }
      else if(mPRICEDIFF_METHOD == HIGH_MINUS_LOW) {
         buf = NormalizeDouble(m_st_PricedataArray[i].high, global_Digits) - NormalizeDouble(m_st_PricedataArray[i].low, global_Digits);
      }
      else {
printf( "[%d]ST2エラー mPRICEDIFF_METHOD=%dが想定外。" , __LINE__,mPRICEDIFF_METHOD);
      
         return false;
      }
      mDiffArray[i] = NormalizeDouble(buf, global_Digits) / global_Points;
      mDataNum++;
/*
if(mPRICEDIFF_METHOD == CLOSE_MINUS_OPEN) {
//printf( "[%d]ST2 差額[%d] 時刻%s   >%s< - >%s< →　>%s<" , __LINE__,
printf( "[%d]ST2 from, to, 差額 %s,%s,%s" , __LINE__,
        DoubleToStr(m_st_PricedataArray[i].close, global_Digits),
        DoubleToStr(m_st_PricedataArray[i].open, global_Digits),        
        DoubleToStr(mDiffArray[i], global_Digits)
         );
   }
else if(mPRICEDIFF_METHOD == HIGH_MINUS_LOW) {      
printf( "[%d]ST2 差額[%d] >%s< - >%s< →　>%s<" , __LINE__, i, 
        DoubleToStr(m_st_PricedataArray[i].high, global_Digits),
        DoubleToStr(m_st_PricedataArray[i].low, global_Digits),        
        DoubleToStr(mDiffArray[i], global_Digits)
         );
   }
else {
printf( "[%d]ST2 差額の計算パターンが不正　>%d<" , __LINE__,mPRICEDIFF_METHOD);
}
*/
   } 
   // 差額の平均及び偏差を計算する。
   bool flag_calcMS = calcMeanAndSigma(mDiffArray, 
                                       mDataNum, 
                                       priceDiff_Mean,
                                       priceDiff_Sigma);
   if(flag_calcMS == false) {
printf( "[%d]ST2エラー calcMeanAndSigmaが失敗" , __LINE__);
   
      priceDiff_Mean  = DOUBLE_VALUE_MIN;
      priceDiff_Sigma = DOUBLE_VALUE_MIN;  
      return false;
   }

   //
   // ２．最頻値を計算する。
   // 
   bool flag_calc_Mode = 
   calc_Mode(mDiffArray,      //　最頻値を求める母集団の配列
             ST2_CLASS_NUM,   // 階級(class)の数
             m_st_classArray  // 出力：第1引数で渡した配列の値を、第2引数で渡した数の階級に分け、各クラスの件数及び最頻値を計算する。
            ); 
   if(flag_calc_Mode == false) {
printf( "[%d]ST2エラー calc_Modeが失敗" , __LINE__);
   
      return false;
   }


   return true;
}



//+------------------------------------------------------------------+
//|   直近の差額を計算する。 ※返り値の単位は、ポイント※                                              |
//+------------------------------------------------------------------+
double get_last_priceDiff(int mPRICEDIFF_METHOD,    // 差額の計算方法
                          int mPRICEDIFF_SHIFT      // 0:現在のBIDかASK - シフト０の始値, 1:シフト１の終値 - シフト１の始値
                      ) {
                     
   double ret = DOUBLE_VALUE_MIN;
   if(mPRICEDIFF_METHOD == CLOSE_MINUS_OPEN) {
      if(mPRICEDIFF_SHIFT == 0) {
         ret = (NormalizeDouble(Bid, global_Digits) - NormalizeDouble(Open[0], global_Digits)) / global_Points;
      }
      else  {
         ret = (NormalizeDouble(Close[mPRICEDIFF_SHIFT], global_Digits) - NormalizeDouble(Open[mPRICEDIFF_SHIFT+1], global_Digits)) / global_Points;
      }
   }
   else if(mPRICEDIFF_METHOD == HIGH_MINUS_LOW) {
      ret = (NormalizeDouble(High[mPRICEDIFF_SHIFT], global_Digits) - NormalizeDouble(Low[mPRICEDIFF_SHIFT], global_Digits)) / global_Points;   
   }
   else {   
      ret = DOUBLE_VALUE_MIN;
   }
/*   
printf( "[%d]ST2　直近の差額計算データ mPRICEDIFF_METHOD=%d  %s  Bid=%s 　Ask=%s Open[0]=%s  Close[1]=%s Open[2]=%s" , __LINE__, 
         mPRICEDIFF_METHOD,
         TimeToStr(Time[0]),
         DoubleToStr(Bid, global_Digits),
         DoubleToStr(Ask, global_Digits),
         DoubleToStr(Open[0], global_Digits),
         DoubleToStr(Close[1], global_Digits),
         DoubleToStr(Open[2], global_Digits)  );
printf( "[%d]ST2　直近の差額計算データ %s  High[0]=%s Low[0]=%s  High[1]=%s Low[1]=%s" , __LINE__, 
         TimeToStr(Time[0]),
         DoubleToStr(High[0], global_Digits),
         DoubleToStr(Low[0], global_Digits),
         DoubleToStr(High[1], global_Digits),
         DoubleToStr(Low[1], global_Digits)  );
  */ 

   
   return ret;
}



//+------------------------------------------------------------------+
//|   金額の平均、偏差を計算する。                                   |
//+------------------------------------------------------------------+
bool get_price_Mean_Sigma(st_Pricedata &m_st_PricedataArray[], // 価格データを格納した配列
                          int           mPRICE_METHOD,        // 差額の計算方法
                          double       &priceMean,      // 出力：平均の計算結果
                          double       &priceSigma     // 出力：偏差の計算結果
                            ) {
/* mPRICE_METHODは、COMMONで定義された次のいずれかの値。
int OPEN_PRICE  = 1;
int HIGH_PRICE  = 2;
int LOW_PRICE   = 3;
int CLOSE_PRICE = 4;     
*/
   
   int i;
   double mPriceArray[MAX_PRICE_NUM];
   int mDataNum = 0;
   // 配列m_st_PricedataArrayから、価格を取得する。
   for(i = 0; i < ArraySize(m_st_PricedataArray); i++) {
      if(m_st_PricedataArray[i].dt <= 0) {
         break;
      }
      double buf = 0.0;
      if(mPRICE_METHOD == OPEN_PRICE) {
         buf = NormalizeDouble(m_st_PricedataArray[i].open, global_Digits);
      }
      else if(mPRICE_METHOD == HIGH_PRICE) {
         buf = NormalizeDouble(m_st_PricedataArray[i].high, global_Digits);
      }
      else if(mPRICE_METHOD == LOW_PRICE) {
         buf = NormalizeDouble(m_st_PricedataArray[i].low, global_Digits);
      }
      else if(mPRICE_METHOD == CLOSE_PRICE) {
         buf = NormalizeDouble(m_st_PricedataArray[i].close, global_Digits);
      }
      else {
printf( "[%d]ST2エラー mPRICE_METHOD=%dが想定外。" , __LINE__,mPRICE_METHOD);
      
         return false;
      }
      mPriceArray[i] = NormalizeDouble(buf, global_Digits);
      mDataNum++;
   } 
   // 金額の平均及び偏差を計算する。
   bool flag_calcMS = calcMeanAndSigma(mPriceArray, 
                                       mDataNum, 
                                       priceMean,
                                       priceSigma);
   if(flag_calcMS == false) {
printf( "[%d]ST2エラー calcMeanAndSigmaが失敗" , __LINE__);
   
      priceMean  = DOUBLE_VALUE_MIN;
      priceSigma = DOUBLE_VALUE_MIN;  
      return false;
   }

   return true;
}


          
//+------------------------------------------------------------------+
//|   グローバル変数の初期値に不適切な値が設定されていれば、falseを返す                                              |
//+------------------------------------------------------------------+
bool checkGlobalParam() {



   return true;
}


//+------------------------------------------------------------------+
//|   外部パラメーターに不適切な値が設定されていれば、falseを返す                                              |
//+------------------------------------------------------------------+

bool checkExternalParam() {
   if(POP_NUM > MAX_PRICE_NUM) {
      printf( "[%d]ST2エラー 母集団の数が、テストで設定できる値以上。" , __LINE__ );
      return false;
   }
   
   if(ST2_PRICEDIFF_SHIFT > 1 || ST2_PRICEDIFF_SHIFT < 0) {
      printf( "[%d]ST2エラー ST2_PRICEDIFF_SHIFTは、０か１" , __LINE__ );
      return false;
   }
   
   return true;
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

double adjustValue = global_Points;

   for(int i = OrdersTotal() - 1; i >= 0;i--) {						
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == true) {
         mMagic = OrderMagicNumber(); 				
         mBUYSELL = OrderType();	
         mOpen = OrderOpenPrice();
	      mSymbol = OrderSymbol();
         
         if( mMagic == magic 
            && StringCompare(mSymbol, symbol) == 0
            && mBUYSELL == buysell) {
            if( MathAbs(mOpen-price) < (ENTRY_WIDTH_PIPS * adjustValue) / DISTANCE  ) {
               return true;
            }  
         }

      }	
   }	
   return false;	
}	



// ST2の取引のうち、comment欄に<TP=%s><SL=%s>の文字列があれば、利確、損切を設定する。
// ただし、既に利確、損切が設定されていれば、何もしない。
// 複数の取引を処置対象とした場合でも、1件でも処理失敗があればfalseを返す。
bool doForcedSettlement_ST2(int mMagic , string mSymbol) {
   int    magic   = 0;
   string symbol  = "";
   double tp      = 0.0;
   double sl      = 0.0;
   double tpPrice_new  = 0.0;
   double slPrice_new  = 0.0;
   string comment = "";
   int buysell    = 0;
   int line_color = -1;
   bool retFlag   = true; // OrderModifyが1度でも失敗すれば、false
   bool flagChange = false;  // tp, slどちらかの更新をする場合にtrue
   
   for(int i = OrdersTotal() - 1; i >= 0;i--) {						
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == true) {
         magic   = OrderMagicNumber(); 				
	      symbol  = OrderSymbol();
         buysell = OrderType();
         comment = OrderComment(); 
         // マジックナンバーと通貨ペア名で絞り込む
         if(mMagic == magic
            && StringCompare(mSymbol, mSymbol) == 0
            && (buysell == OP_BUY || buysell == OP_SELL) 
            ) {
	               
            tpPrice_new = DOUBLE_VALUE_MIN;
            slPrice_new = DOUBLE_VALUE_MIN;
               
            if(buysell == OP_BUY) {
               line_color = LINE_COLOR_LONG;
            }
            else if(buysell == OP_SELL) {
               line_color = LINE_COLOR_SHORT;
            }
            
            // commentから、当初予定の利確損切値を切り出す               
            bool flag_get_TPSL_fromComment = 
            get_TPSL_fromComment(comment,  // 検索文字列
                                 tpPrice_new,   // 出力：検索文字列内に<TP=%s>があれば、%sをdouble型にして返す
                                 slPrice_new    // 出力：検索文字列内に<SL=%s>があれば、%sをdouble型にして返す
                                 );
            // commentから利確、損切の抽出に成功し、少なくとも一方は抽出できた時は更新作業を続ける。
            if(flag_get_TPSL_fromComment == true
               && (tpPrice_new > 0.0 || slPrice_new > 0.0) ) {
 
               double tp_line = DOUBLE_VALUE_MIN; // 利確できる境界値
               double sl_line = DOUBLE_VALUE_MIN; // 損切できる境界値
               flagChange = false;
               bool flag_calc_ModifyablePrice = calc_ModifyablePrice(buysell, Bid, Ask, tp_line, sl_line);
               if(flag_calc_ModifyablePrice == true) {
                  // 変数tp, slの更新漏れを防ぐため、使わないケースであっても、現在の設定値を変数に入力する。
                  tp = OrderTakeProfit();
                  sl = OrderStopLoss();
                  
                  // コメントから抽出したtp(sl)値が、0でない場合は、抽出値が、tp(sl)の境界を越えて、かつ、有利な条件の値でmodifyする。
                  if(buysell == OP_BUY) {
                     if(tpPrice_new > 0.0 && NormalizeDouble(tpPrice_new, global_Digits) > NormalizeDouble(tp_line, global_Digits) && NormalizeDouble(tpPrice_new, global_Digits) > NormalizeDouble(tp, global_Digits)) {
                        tp = tpPrice_new;  
                        flagChange = true;
                     }
                     if(slPrice_new > 0.0 && NormalizeDouble(slPrice_new, global_Digits) < NormalizeDouble(sl_line, global_Digits) && NormalizeDouble(slPrice_new, global_Digits) < NormalizeDouble(sl, global_Digits)) {
                        sl = slPrice_new;
                        flagChange = true;                        
                     }
                  }
                  if(buysell == OP_SELL) {
                     if(tpPrice_new > 0.0 && NormalizeDouble(tpPrice_new, global_Digits) < NormalizeDouble(tp_line, global_Digits) && NormalizeDouble(tpPrice_new, global_Digits) < NormalizeDouble(tp, global_Digits)) {
                        tp = tpPrice_new; 
                        flagChange = true;                         
                     }
                     
                     if(slPrice_new > 0.0 && NormalizeDouble(slPrice_new, global_Digits) > NormalizeDouble(sl_line, global_Digits) && NormalizeDouble(slPrice_new, global_Digits) > NormalizeDouble(sl, global_Digits)) {
                        sl = slPrice_new;
                        flagChange = true;                        
                     }

                     
                  }

                  if( flagChange == true && (buysell == OP_BUY || buysell == OP_SELL) ) { 
                     bool mFlag = OrderModify(OrderTicket(), OrderOpenPrice(), tp, sl, 0, line_color);
                     if(mFlag != true) {
                        printf( "[%d]エラー オーダーの修正失敗：%s 修正前tp=%s sl=%s  tp=%s sl=%s" , __LINE__, GetLastError(), 
                                 DoubleToStr(OrderTakeProfit(), global_Digits), DoubleToStr(OrderStopLoss(), global_Digits),
                                 DoubleToStr(tp, global_Digits), DoubleToStr(sl, global_Digits));
                        retFlag = false;
                     }
                  }
               }
            }
         }	
      }	
   }
      
   return retFlag;
}


bool get_TPSL_fromComment(string mcomment, // 検索文字列
                          double &mTP_new, // 出力：検索文字列内に<TP=%s>があれば、%sをdouble型にして返す
                          double &mSL_new  // 出力：検索文字列内に<SL=%s>があれば、%sをdouble型にして返す
                          ){
   bool retFlag = false;  // TP, SLどちらかがデータ取得成功すれば、true
   int TP_Position = -1; // 先頭位置に見つかった時は、０
   int SL_Position = -1; // 先頭位置に見つかった時は、０
   int next_position = 0;
   int find_start_position = 0; // 文字検索をする最初の位置。最初の文字は0（1ではない）
   string bufPrice = "";
   TP_Position = StringFind(mcomment, "<TP=", find_start_position);
   SL_Position = StringFind(mcomment, "<SL=", find_start_position);
   
   // キーワードが含まれていなければ、falseを返す。
   if(TP_Position < 0 && SL_Position < 0){
      return false;
   }
   
   // TP抽出
   if(TP_Position >= 0){
      // <TP=の次の>を探す
      find_start_position = TP_Position + 1;
      next_position = StringFind(mcomment, ">", find_start_position);
      if(next_position > find_start_position){
         bufPrice = StringSubstr(mcomment, find_start_position - 1 + StringLen("<TP="), next_position - (find_start_position + StringLen("TP=")) );
//         printf("[%d]ST2テスト comment=***%s*** TP開始位置=%d 終わり記号開始位置=%d　切り取り文字列", __LINE__, mcomment, find_start_position, next_position);
         mTP_new = NormalizeDouble(StrToDouble(bufPrice), global_Digits);

//         printf("[%d]ST2テスト mTP_new 文字列=***%s*** 数値=%s", __LINE__, bufPrice, DoubleToStr(mTP_new, global_Digits));
         retFlag = true;
      }
   }

   // SL抽出   
   if(SL_Position >= 0){
      // <TP=の次の>を探す
      find_start_position = SL_Position + 1;
      next_position = StringFind(mcomment, ">", find_start_position);
      if(next_position > find_start_position) {
         bufPrice = StringSubstr(mcomment, find_start_position - 1 + StringLen("<SL="), next_position - (find_start_position + StringLen("SL="))  );
         mSL_new = NormalizeDouble(StrToDouble(bufPrice), global_Digits);
 //        printf("[%d]ST2テスト mSL_new 文字列=***%s*** 数値=%s", __LINE__, bufPrice, DoubleToStr(mSL_new, global_Digits));
         retFlag = true;
      }
   }
   return retFlag;
}                          


