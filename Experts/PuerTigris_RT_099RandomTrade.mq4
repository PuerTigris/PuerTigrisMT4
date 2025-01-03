//20221108 新規作成


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

#include <Puer_RandomTrade.mqh>	 
//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
//

//
// 099RandomTrade専用
//
extern string PuerTigrisRTTitle    = "---RTのパラメータ---";
extern int    MagicNumberRT        = 90000099;
extern int    G_RTMethod = 1;           // 1:ランダムに売買を判断する。2:トレンドも考慮して売買を判断する
extern double G_RTthreshold_PER = 50.0; // 売買判断をする閾値（threshold）。乱数(0～32767)が、32767 * RTthreshold_PER / 100以上なら売り。未満なら、買い。


//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
string PGName = "PuerTigris"; //プログラム名		
//
// 099RandomTrade専用
//
datetime RTtime0 = 0;                                  //　EAが大量のオーダーを重複して出力するのを避けるための変数。

datetime CONTROLALLtime0 = 0;//足1本で1回の処理をするための変数




//+------------------------------------------------------------------+	
//| 初期処理                                                         |	
//+------------------------------------------------------------------+	
int init() {	
/*
double tmpTPPips;
double tmpSLPips;
tmpTPPips = change_PiPS2PointTP_PIPS);
tmpSLPips = change_PiPS2PointSL_PIPS);
printf( "[%d]RT 設定値 改善版　TP_PIPS=%s  SL_PIPS =%s   通貨ペア=%s  換算値　TP=%s pips  SL=%s pips 計算例ASK+TP=%s + %s = %s" , __LINE__,
DoubleToStr(TP_PIPS, global_Digits),
DoubleToStr(SL_PIPS, global_Digits),
Symbol(),
DoubleToStr(tmpTPPips, global_Digits),
DoubleToStr(tmpSLPips, global_Digits),
DoubleToStr(Ask, global_Digits),
DoubleToStr(tmpTPPips, global_Digits),
DoubleToStr(Ask + tmpTPPips, global_Digits)
);
printf( "[%d]RT 設定値 従来版　TP_PIPS=%s  SL_PIPS =%s   通貨ペア=%s  換算値　TP=%s pips  SL=%s pips 計算例ASK+TP=%s + %s = %s" , __LINE__,
DoubleToStr(TP_PIPS, global_Digits),
DoubleToStr(SL_PIPS, global_Digits),
Symbol(),
DoubleToStr(TP_PIPS * global_Points, global_Digits),
DoubleToStr(SL_PIPS * global_Points, global_Digits),
DoubleToStr(Ask, global_Digits),
DoubleToStr(TP_PIPS * global_Points, global_Digits),
DoubleToStr(Ask + TP_PIPS * global_Points, global_Digits)
);
*/
   //オブジェクトの削除	
   MyObjectsDeleteAll();

   updateExternalParamCOMM();

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
printf( "[%d]PB init：ストップレベル=%s" , __LINE__ , DoubleToStr(global_StopLevel, global_Digits));
   
   // 乱数発生用のシード
   RTTickCount = GetTickCount();
   MathSrand(RTTickCount);    // シードの設定。

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
int start() {
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
   //
   // PING_WEIGHT_MINS分間隔で、以下の処理を実行する。
   //
   if(TimeCurrent() - CONTROLALLtime0 >= Period() * 60) { // 
      CONTROLALLtime0 = TimeCurrent();
   }
   else {
      return 1;
   }	

    //
   // 実取引のメモリ呼び出し
   //
   // 実行時点で未決済取引をグローバル変数に読み出す。
   read_OpenTrades(MagicNumberRT);
   

   // 実取引を行う
   entryRandomTrade(MagicNumberRT);
   
   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、全オーダーの指値と逆指値をセットする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      update_AllOrdersTPSL(global_Symbol, MagicNumberRT, TP_PIPS, SL_PIPS);
   } 

   //最小利食値FLOORINGが設定されていれば、損切値の更新を試す。
   if(FLOORING >= 0) {
      flooringSL(global_Symbol, MagicNumberRT, FLOORING, FLOORING_CONTINUE);
   }

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、マジックナンバーをキーとして強制決済をする。
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      do_ForcedSettlement(MagicNumberRT, global_Symbol, TP_PIPS, SL_PIPS);
   } 

   return(0);	
}	
	

//
// 外部パラメータをグローバル変数にコピーする。
//
void update_GlobalParam_to_ExternalParam() {
   RTMethod        = G_RTMethod;        // 1:ランダムに売買を判断する。2:トレンドも考慮して売買を判断する
   RTthreshold_PER = G_RTthreshold_PER; // 売買判断をする閾値（threshold）。乱数(0～32767)が、32767 * RTthreshold_PER / 100以上なら売り。未満なら、買い。
}


//+------------------------------------------------------------------+
//| RandomTrade                                        　　　　      |
//+------------------------------------------------------------------+
bool entryRandomTrade(int mMagic){
   // 戦略別mqhの関数を呼ぶ前に、外部パラメータをグローバル変数にコピーする。
   update_GlobalParam_to_ExternalParam();						

   // 同時に多数発注するのを防ぐ。
   datetime tradeTime = TimeLocal();


   // 戦略別mqhの関数を使用する。
   int mSignal = entryRandomTrade();

   bool mFlag = false;
   double sl = 0.0;
   double tp = 0.0;
   int ticket_num = 0;
   

   if( mSignal == BUY_SIGNAL) {
      double mMarketinfoMODE_ASK = MarketInfo(global_Symbol,MODE_ASK);
      tp = mMarketinfoMODE_ASK + NormalizeDouble(change_PiPS2Point(TP_PIPS), global_Digits); // 利確の候補
      sl = mMarketinfoMODE_ASK - NormalizeDouble(change_PiPS2Point(SL_PIPS), global_Digits); // 損切の候補 
/*
printf( "[%d]買い TP=%s sl=%s　TP_PIPS=%s SL_PIPS=%s" , __LINE__ , 
DoubleToStr(tp, global_Digits),
DoubleToStr(sl, global_Digits),
DoubleToStr(TP_PIPS, global_Digits),
DoubleToStr(SL_PIPS, global_Digits)
);
*/
      ticket_num = mOrderSend4_NOCHECK(global_Symbol,OP_BUY,LOTS,Ask,SLIPPAGE, sl, tp,changeMagicToString(mMagic),mMagic,0, LINE_COLOR_LONG);	
      if(ticket_num > 0){
         RTtime0 = tradeTime;
      }
      else if(ticket_num == ERROR_ORDERSEND) {
         printf( "[%d]エラー 買い発注の失敗::%d" , __LINE__ , ticket_num);
         return false;
      } 
   }
   else if(mSignal == SELL_SIGNAL) {
      double mMarketinfoMODE_BID = MarketInfo(global_Symbol,MODE_BID);
      tp = mMarketinfoMODE_BID - NormalizeDouble(change_PiPS2Point(TP_PIPS), global_Digits); // 利確の候補
      sl = mMarketinfoMODE_BID + NormalizeDouble(change_PiPS2Point(SL_PIPS), global_Digits); // 損切の候補 
/*printf( "[%d]売り TP=%s sl=%s　TP_PIPS=%s SL_PIPS=%s" , __LINE__ , 
DoubleToStr(tp, global_Digits),
DoubleToStr(sl, global_Digits),
DoubleToStr(TP_PIPS, global_Digits),
DoubleToStr(SL_PIPS, global_Digits)
);*/      
      ticket_num = mOrderSend4_NOCHECK(global_Symbol,OP_SELL,LOTS,Bid,SLIPPAGE,sl, tp,changeMagicToString(mMagic),mMagic,0,LINE_COLOR_SHORT);
      if(ticket_num > 0) {
         RTtime0 = tradeTime;
      }
      else if(ticket_num == ERROR_ORDERSEND) {
         printf( "[%d]エラー 売り発注の失敗::%d" , __LINE__ , ticket_num);
         return false;
      } 
   }
   else {
      return false;
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
if(mag == MagicNumberRT) {
         strBuf = g_StratName99;
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


