//
// 20221024CORRのみのEAとして、新規作成
// 20230502 仮想取引を除去。PuerTigris_SR_012SAR.mq4を基に他のファイルの処理を共通化。



//+------------------------------------------------------------------+	
//|  Copyright (c) 2016 トラの親 All rights reserved.                |	
//|                                                                  |
//+------------------------------------------------------------------+	
#property copyright "Copyright (c) 2016 トラの親 All rights reserved."				
#property link      "http://nenshuuha.blog.fc2.com/"						
//+------------------------------------------------------------------+	
//| ヘッダーファイル読込                                             |	
//+------------------------------------------------------------------+	
#include <stderror.mqh>	
#include <stdlib.mqh>	
#include <Tigris_COMMON.mqh>
#include <Tigris_TradingLine.mqh>

#include <Puer_CORR.mqh>	 
//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
extern int    MagicNumberCORR        = 90000018;

extern string PuerTigrisCORRTitle    = "---CORRのパラメータ---";
extern int    G_CORREL_TF_SHORTER = 1;    //0から9。2は、PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
extern int    G_CORREL_TF_LONGER  = 5;    //0から9。PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
extern double G_CORRELLower       = -0.225; //-1.0～+1.0。2つのタイムフレーム間の相関係数のため、絶対値は1未満。
extern double G_CORRELHigher      = 0.225;  //-1.0～+1.0。2つのタイムフレーム間の相関係数のため、絶対値は1未満。
extern int    G_CORREL_period     = 200;
extern int    G_MAX_OPEN_TRADENUM = 2;    // 同時にオープンな状態の取引がいくつまで許すか。

//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
string PGName = "PuerTigris"; //プログラム名				
 
int    OPT_MIN_TRADENUM = 5;            // パラメータセット選定用。最適化の実行に必要な仮想取引数の最小値。この件数以上のパラメータセットが選定対象。通常は、5
double WINNING_PER_LOSE_RATE_MIN = 1.5; // パラメータセット選定用。パラメータセット別の勝ち数÷負け数がこの値以上をパラメータセットが選定対象。通常は、1.0
double PROFITFACTOR_MIN = 1.01;         // パラメータセット選定用。プロフィットファクターがこの値以上のパラメータセットが選定対象。通常は、1.01
//
// 018CORR専用
//  
datetime CORRtime0 = 0;                                    //　EAが大量のオーダーを重複して出力するのを避けるための変数。
datetime CONTROLALLtime0 = 0;//足1本で1回の処理をするための変数




//+------------------------------------------------------------------+	
//| 初期処理                                                         |	
//+------------------------------------------------------------------+	
int init() {	
   //オブジェクトの削除	
   MyObjectsDeleteAll();

   updateExternalParamCOMM();
   updateExternalParam_TradingLine();
   
   // 初期状態の外部パラメータをグローバル変数にコピーする。
   update_GlobalParam_to_ExternalParam();
   
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

   // 現在のシフトでトレーディングラインを計算する
   ENUM_TIMEFRAMES TIME_FRAME_MAXMIN_ENUM = changeInt2ENUMTIMEFRAME(TIME_FRAME_MAXMIN);
   bool flag_calc_TradingLines = calc_TradingLines(global_Symbol, 
                                                   TIME_FRAME_MAXMIN_ENUM, 
                                                   SHIFT_SIZE_MAXMIN, 
                                                   g_past_max, 
                                                   g_past_maxTime, 
                                                   g_past_min, 
                                                   g_past_minTime, 
                                                   g_past_width, 
                                                   g_long_Min, 
                                                   g_long_Max, 
                                                   g_short_Min, 
                                                   g_short_Max);

   if(flag_calc_TradingLines == false) {
  	   return -1;
   }
   return(INIT_SUCCEEDED);	
}	
	
//+------------------------------------------------------------------+	
//| 終了処理                                                         |	
//+------------------------------------------------------------------+	
int deinit() {	
   //オブジェクトの削除	
   MyObjectsDeleteAll();

   return(0);	
}	
	
//+------------------------------------------------------------------+	
//| メイン処理                                                       |	
//+------------------------------------------------------------------+	
int start()	
{
   if(checkExternalParam() != true) {
      printf( "[%d]エラー 外部パラメーターに不適切な値あり" , __LINE__);
      return -1;
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
   string err_title02     = "[例外エラー] ";                  //エラーメッセージタイトル02			   
   int shift_value = 1;                                       //MAやCloseを計算するときのシフト値		
   
   datetime timeCurr = TimeCurrent();
   double tmpBID = 0.0;
   double tmpASK = 0.0;
   ENUM_TIMEFRAMES TIME_FRAME_MAXMIN_ENUM = changeInt2ENUMTIMEFRAME(TIME_FRAME_MAXMIN);

   ShowTestMsg = false;

/*   
   // PING_WEIGHT_MINS分間隔で、以下の処理を実行する。
   if(TimeCurrent() - CONTROLALLtime0 >= PING_WEIGHT_MINS * 60) { // 
      CONTROLALLtime0 = TimeCurrent();
   }
   else {
      return ERROR;
   }	
 */	

   //
   // トレーディングラインの更新
   //
   // BIDが過去最大値を超えた場合は、トレンドが大きく変わったと判断して、トレーディングラインを見直し
   tmpBID = NormalizeDouble(Bid, global_Digits);
   if(g_past_max > 0.0 
      && NormalizeDouble(g_past_max, global_Digits) < NormalizeDouble(tmpBID, global_Digits)) {  
      update_TradingLines(global_Symbol, 
                          TIME_FRAME_MAXMIN_ENUM, 
                          SHIFT_SIZE_MAXMIN);
   }

   // ASKが過去最小値を下回った場合は、トレンドが大きく変わったと判断して、トレーディングラインを見直し
   tmpASK = NormalizeDouble(Ask, global_Digits);
   if(g_past_min > 0.0 
      && NormalizeDouble(g_past_min, global_Digits) > NormalizeDouble(tmpASK, global_Digits)) {  
      update_TradingLines(global_Symbol, 
                          TIME_FRAME_MAXMIN_ENUM, 
                          SHIFT_SIZE_MAXMIN);        
   }

   if(CORRtime0 != Time[0] && is_TradablePrice() >= 0) {
      int openTradeNum = -1;
     
      openTradeNum = get_OpenTradeNum(MagicNumberCORR);
      if(openTradeNum < G_MAX_OPEN_TRADENUM) {      
         // 実取引を行う
         orderByCORREL_TIME(MagicNumberCORR);
      }
   }   

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、全オーダーの指値と逆指値をセットする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      update_AllOrdersTPSL(global_Symbol, MagicNumberCORR, TP_PIPS, SL_PIPS);
   } 

   //最小利食値FLOORINGが設定されていれば、損切値の更新を試す。
   if(FLOORING >= 0) {
      flooringSL(global_Symbol, MagicNumberCORR, FLOORING, FLOORING_CONTINUE);
   }

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、マジックナンバーをキーとして強制決済をする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      do_ForcedSettlement(MagicNumberCORR, global_Symbol, TP_PIPS, SL_PIPS);
   } 

      return(0);	
}	
	

//
// 外部パラメータをグローバル変数にコピーする。
//
void update_GlobalParam_to_ExternalParam() {
   CORREL_TF_SHORTER = G_CORREL_TF_SHORTER; //0から9。2は、PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
   CORREL_TF_LONGER  = G_CORREL_TF_LONGER; //0から9。PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
   CORRELHigher      = G_CORRELHigher; //-1.0～+1.0
   CORRELLower       = G_CORRELLower; //-1.0～+1.0
   CORREL_period     = G_CORREL_period;
}


//+------------------------------------------------------------------+
//| CORRを使った実取引                                 　　　　      |
//+------------------------------------------------------------------+
bool orderByCORREL_TIME(int mMagic){
   // 戦略別mqhの関数を呼ぶ前に、外部パラメータをグローバル変数にコピーする。
   update_GlobalParam_to_ExternalParam();						

   // 同時に多数発注するのを防ぐ。
   datetime tradeTime = Time[0];

   // 戦略別mqhの関数を使用する。
   int buysellSignal = orderByCORREL_TIME();

   int intTrend = NoTrend;
   bool mFlag = false;
   double sl = 0.0;
   double tp = 0.0;
   int ticket_num = 0;
   
   bool flag_read_TradingLines;
   double   past_max;     // 過去の最高値
   datetime past_maxTime; // 過去の最高値の時間
   double   past_min;     // 過去の最安値
   datetime past_minTime; // 過去の最安値の時間
   double   past_width;   // 過去値幅。past_max - past_min
   double   long_Min;     // ロング取引を許可する最小値
   double   long_Max;     // ロング取引を許可する最大値
   double   short_Min;    // ショート取引を許可する最小値
   double   short_Max;    // ショート取引を許可する最大値   
   if(buysellSignal == BUY_SIGNAL || buysellSignal == SELL_SIGNAL) {
      flag_read_TradingLines = read_TradingLines(past_max,  // 出力：過去の最高値
                                              past_maxTime,   // 出力：過去の最高値の時間
                                              past_min,       // 出力：過去の最安値
                                              past_minTime,   // 出力：過去の最安値の時間
                                              past_width,     // 出力：過去値幅。past_max - past_min
                                              long_Min,       // 出力：ロング取引を許可する最小値
                                              long_Max,       // 出力：ロング取引を許可する最大値
                                              short_Min,      // 出力：ショート取引を許可する最小値
                                              short_Max       // 出力：ショート取引を許可する最大値
                                            );   
   }

   double mMarketinfoMODE_ASK;
   double mMarketinfoMODE_BID;


   // 4時間足の傾きでシグナルを見直す。
   if(buysellSignal == BUY_SIGNAL || buysellSignal == SELL_SIGNAL) {
      int trend = get_Trend_EMA_PERIODH4(global_Symbol, 0);
      if(buysellSignal == BUY_SIGNAL && trend == DownTrend) {
         buysellSignal = NO_SIGNAL;
      }
      else if(buysellSignal == SELL_SIGNAL && trend == UpTrend) {
         buysellSignal = NO_SIGNAL;         
      }
   }
      
   // トレーディングラインとENTRY_WIDTH_PIPSを使って、発注予定値が条件を満たすかどうかを判断する。
   // 発注不可の値であれば、シグナルをNO_SIGNALに変更する。
   bool flag_is_TradablePrice;
   if( buysellSignal == BUY_SIGNAL) {
      mMarketinfoMODE_ASK = MarketInfo(global_Symbol,MODE_ASK);   
      flag_is_TradablePrice = 
         is_TradablePrice(mMagic,
                                     BUY_SIGNAL,
                                     long_Max,
                                     long_Min,
                                     ENTRY_WIDTH_PIPS,     // 何PIPSの間隔をあけるか
                                     mMarketinfoMODE_ASK); // 発注予定値
      if(flag_is_TradablePrice == false) {
         buysellSignal = NO_SIGNAL;
      }
   }
   else if( buysellSignal == SELL_SIGNAL) {
      mMarketinfoMODE_BID = MarketInfo(global_Symbol,MODE_BID);
      flag_is_TradablePrice = 
         is_TradablePrice(mMagic,
                                     SELL_SIGNAL,
                                     short_Max,
                                     short_Min,
                                     ENTRY_WIDTH_PIPS,     // 何PIPSの間隔をあけるか
                                     mMarketinfoMODE_ASK); // 発注予定値
      if(flag_is_TradablePrice == false) {
         buysellSignal = NO_SIGNAL;
      }
   }   
   
   // オシレータ系テクニカル指標を使った売買判断
   int WPR_Signal;
   int RSI_Signal;
   int STOC_Signal;
   int Total_Signal;
   if(buysellSignal == BUY_SIGNAL || buysellSignal == SELL_SIGNAL) {
      int flagOsci = judge_BuySellSignal_Oscillator(global_Symbol,
                                                    WPR_Signal, // WPRを使ったシグナル。BUY_SIGNAL, SELL_SIGNAL, NO_SIGNAL
                                                    RSI_Signal, // RSIを使ったシグナル。BUY_SIGNAL, SELL_SIGNAL, NO_SIGNAL
                                                    STOC_Signal, // Stochasticを使ったシグナル。BUY_SIGNAL, SELL_SIGNAL, NO_SIGNAL
                                                    Total_Signal // 3つのシグナルのうち1つ以上がBUY_SIGNALかつSELL_SIGNALが無ければ、BUY_SIGNAL
                                      );

      if(buysellSignal == BUY_SIGNAL && flagOsci == SELL_SIGNAL) {
         buysellSignal = NO_SIGNAL;
      }
      else if(buysellSignal == SELL_SIGNAL && flagOsci == BUY_SIGNAL) {
         buysellSignal = NO_SIGNAL;         
      }
   }
      
   if(CORRtime0 != tradeTime) {
      if( buysellSignal == BUY_SIGNAL) {
         tp = mMarketinfoMODE_ASK + NormalizeDouble(change_PiPS2Point(TP_PIPS), global_Digits); // 利確の候補
         sl = mMarketinfoMODE_ASK - NormalizeDouble(change_PiPS2Point(SL_PIPS), global_Digits); // 損切の候補 
   
         ticket_num = mOrderSend5(global_Symbol,OP_BUY,LOTS,mMarketinfoMODE_ASK,SLIPPAGE, sl, tp,changeMagicToString(mMagic),mMagic,0, LINE_COLOR_LONG);	
         if(ticket_num > 0){
            CORRtime0 = tradeTime;
         }
         else if(ticket_num == ERROR_ORDERSEND) {
            printf( "[%d]エラー 買い発注の失敗::%d" , __LINE__ , ticket_num);
            return false;
         } 
      }
      else if(buysellSignal == SELL_SIGNAL) {
         tp = mMarketinfoMODE_BID - NormalizeDouble(change_PiPS2Point(TP_PIPS), global_Digits); // 利確の候補
         sl = mMarketinfoMODE_BID + NormalizeDouble(change_PiPS2Point(SL_PIPS), global_Digits); // 損切の候補 
         
         ticket_num = mOrderSend5(global_Symbol,OP_SELL,LOTS,mMarketinfoMODE_BID,SLIPPAGE,sl, tp,changeMagicToString(mMagic),mMagic,0,LINE_COLOR_SHORT);
         if(ticket_num > 0) {
            CORRtime0 = tradeTime;
         }
         else if(ticket_num == ERROR_ORDERSEND) {
            printf( "[%d]エラー 売り発注の失敗::%d" , __LINE__ , ticket_num);
            return false;
         } 
      }
      else {
         return false;
      }
   }
   return true;
}







//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|   共通関数　　　                                                 |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|   定時メール送信                                                 |
//+------------------------------------------------------------------+	
// 利用していないため、void SendMailOrg(int mailtime1, int mailtime2)を削除
// 作成する場合は、OpenTrade_BuySell[MAX_TRADE_NUM];を使うこと。

//+------------------------------------------------------------------+
//| マジックナンバー（数値）を戦略名（文字列）に変換する　　　                     　　　　　      |
//+------------------------------------------------------------------+
string changeMagicToString(int mag) {
   string strBuf = "";
if(mag == MagicNumberCORR) {
         strBuf = g_StratName18;
   }
   else { 
         strBuf = "MN" + IntegerToString(mag, 10);
   } 
   return strBuf;
}


bool checkExternalParam() {
   // 現在は、該当する処理無し   
   return true;
}

