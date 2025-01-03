// 20221215WPRのみのEAとして、新規作成
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

#include <Puer_WPR.mqh>	 
//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
extern int    MagicNumberWPR        = 90000008;

extern string No08_WPRTitle = "08.---ウィリアムズWPRに係るパラメータ---";
extern double G_WPRLow         = -60;	//ウィリアムズWPRのLow						
extern double G_WPRHigh        = -40;	//ウィリアムズWPRのHigh	「-20%を超えれば買われ過ぎで「売りサイン」
extern int    G_WPRgarbage     = 100;//過去WPRgarbage個のWPRのうち、WPRgarbageRate％の割合で
		                               //WPRLowを下回っている個数があれば売りとみなす（ガーベージボトム）
extern double G_WPRgarbageRate = 20.0;
extern int    G_MAX_OPEN_TRADENUM = 2;    // 同時にオープンな状態の取引がいくつまで許すか。



//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
string PGName = "PuerTigris"; //プログラム名				
 

datetime WPRtime0 = 0;  //　EAが大量のオーダーを重複して出力するのを避けるための変数。

datetime CONTROLALLtime0 = 0;//足1本で1回の処理をするための変数



//+------------------------------------------------------------------+	
//| 初期処理                                                         |	
//+------------------------------------------------------------------+	
int init() {	
   //オブジェクトの削除	
   MyObjectsDeleteAll();
//printf( "[%d]WPR init：ストップレベル=%s" , __LINE__ , DoubleToStr(global_StopLevel, global_Digits));

   updateExternalParamCOMM();

   // 初期状態の外部パラメータをグローバル変数にコピーする。
   update_GlobalParam_to_ExternalParam();
   updateExternalParam_TradingLine();
   
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

   ShowTestMsg = false;
   ENUM_TIMEFRAMES TIME_FRAME_MAXMIN_ENUM = changeInt2ENUMTIMEFRAME(TIME_FRAME_MAXMIN);
   
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

   if(WPRtime0 != Time[0] && is_TradablePrice() >= 0) {
      int openTradeNum = -1;
     
      openTradeNum = get_OpenTradeNum(MagicNumberWPR);
      if(openTradeNum < G_MAX_OPEN_TRADENUM) {      
         entryWPR(MagicNumberWPR);
      }
      else {
         printf( "[%d] 同時オープン可能な%d件をオーバーするため、実取引の検討せず。" , __LINE__ , G_MAX_OPEN_TRADENUM);
      }       
   }  

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、全オーダーの指値と逆指値をセットする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      update_AllOrdersTPSL(global_Symbol, MagicNumberWPR, TP_PIPS, SL_PIPS);
   } 

   //最小利食値FLOORINGが設定されていれば、損切値の更新を試す。
   if(FLOORING >= 0) {
      flooringSL(global_Symbol, MagicNumberWPR, FLOORING, FLOORING_CONTINUE);
   }

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、マジックナンバーをキーとして強制決済をする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      do_ForcedSettlement(MagicNumberWPR, global_Symbol, TP_PIPS, SL_PIPS);
   } 
   return(0);	
}	
	

//
// 外部パラメータをグローバル変数にコピーする。
//
void update_GlobalParam_to_ExternalParam() {
   WPRLow         = G_WPRLow         = -60;	//ウィリアムズWPRのLow						
   WPRHigh        = G_WPRHigh        = -40;	//ウィリアムズWPRのHigh	「-20%を超えれば買われ過ぎで「売りサイン」
   WPRgarbage     = G_WPRgarbage     = 100;//過去WPRgarbage個のWPRのうち、WPRgarbageRate％の割合でWPRLowを下回っている個数があれば売りとみなす（ガーベージボトム）
   WPRgarbageRate = G_WPRgarbageRate = 20.0;
}


//+------------------------------------------------------------------+
//|                 　　　　      |
//+------------------------------------------------------------------+
bool entryWPR(int mMagic){
   // 戦略別mqhの関数を呼ぶ前に、外部パラメータをグローバル変数にコピーする。
   update_GlobalParam_to_ExternalParam();						

   // 戦略別mqhの関数を使用する。
   
   int buysellSignal = entryRangeWPR();

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
      ENUM_TIMEFRAMES TIME_FRAME_MAXMIN_ENUM = changeInt2ENUMTIMEFRAME(TIME_FRAME_MAXMIN);
   
      update_TradingLines(global_Symbol, 
                          TIME_FRAME_MAXMIN_ENUM, 
                          SHIFT_SIZE_MAXMIN);
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
//printf( "[%d] get_Trend_EMA_PERIODH4で傾きを検証し、ノーシグナルにした" , __LINE__);
      
         buysellSignal =NO_SIGNAL;
      }
      else if(buysellSignal == SELL_SIGNAL && trend == UpTrend) {
//printf( "[%d] get_Trend_EMA_PERIODH4で傾きを検証し、ノーシグナルにした" , __LINE__);
      
         buysellSignal =NO_SIGNAL;         
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
   if( buysellSignal == SELL_SIGNAL) {
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
   datetime tradeTime = Time[0];
   if(WPRtime0 != tradeTime) { 
      if( buysellSignal == BUY_SIGNAL) {
   
         tp = mMarketinfoMODE_ASK + NormalizeDouble((double)TP_PIPS * global_Points, global_Digits); // 利確の候補
         sl = mMarketinfoMODE_ASK - NormalizeDouble((double)SL_PIPS * global_Points, global_Digits); // 損切の候補 
   
         ticket_num = mOrderSend5(global_Symbol,OP_BUY,LOTS,mMarketinfoMODE_ASK,SLIPPAGE, sl, tp,changeMagicToString(mMagic),mMagic,0, LINE_COLOR_LONG);	
         if(ticket_num > 0){
            WPRtime0 = tradeTime;
         }
         else if(ticket_num == ERROR_ORDERSEND) {
            printf( "[%d]エラー 買い発注の失敗::%d" , __LINE__ , ticket_num);
            return false;
         } 
      }
      else if(buysellSignal == SELL_SIGNAL) {
         tp = mMarketinfoMODE_BID - NormalizeDouble((double)TP_PIPS*global_Points, global_Digits); // 利確の候補
         sl = mMarketinfoMODE_BID + NormalizeDouble((double)SL_PIPS*global_Points, global_Digits); // 損切の候補 
         
         ticket_num = mOrderSend5(global_Symbol,OP_SELL,LOTS,mMarketinfoMODE_BID,SLIPPAGE,sl, tp,changeMagicToString(mMagic),mMagic,0,LINE_COLOR_SHORT);
         if(ticket_num > 0) {
            WPRtime0 = tradeTime;
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


//+------------------------------------------------------------------+
//| マジックナンバー（数値）を戦略名（文字列）に変換する　　　                     　　　　　      |
//+------------------------------------------------------------------+
string changeMagicToString(int mag) {
   string strBuf = "";
if(mag == MagicNumberWPR) {
         strBuf = g_StratName08;
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

