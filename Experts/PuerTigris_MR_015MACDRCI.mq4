// 20220617MACDRCIのみのEAとして、新規作成
//
//
//
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

#include <Puer_MACDRCI.mqh>	 
//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
extern int MagicNumberMACDRCI   = 90000015;


extern string No15_MACDRCITitle="15.---MACDRCIの設定---";
extern double G_RCIhighLine =  90.0;//
extern double G_RCIlowLine  = -90.0;//
extern int    G_MAX_OPEN_TRADENUM = 2;    // 同時にオープンな状態の取引がいくつまで許すか。


//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
string PGName = "PuerTigris";             //プログラム名				

bool mMailFlag = true;           //確定損益メールの送信フラグ。trueで送信する。						
bool global_flag_StopTradeUpper = false;
bool global_flag_StopTradeLower = false;

//足1本で1回の処理をするための変数
datetime CONTROLALLtime0 = 0;

//EAが大量のオーダーを重複して出力するのを避けるための変数。
datetime MACDRCItime0 = 0;     

//+------------------------------------------------------------------+	
//| 初期処理                                                         |	
//+------------------------------------------------------------------+	
int init()	
{	
   //オブジェクトの削除	
   ObjectsDeleteAll();

   updateExternalParamCOMM();

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
   ObjectsDeleteAll();
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

  
   if(MACDRCItime0 != Time[0] && is_TradablePrice() >= 0) {
      int openTradeNum = -1;
     
      openTradeNum = get_OpenTradeNum(MagicNumberMACDRCI);
      if(openTradeNum < G_MAX_OPEN_TRADENUM) {   
         
         entryMACDRCI2(MagicNumberMACDRCI); 
      }
      else {
         printf( "[%d] 同時オープン可能な%d件をオーバーするため、実取引の検討せず。" , __LINE__ , G_MAX_OPEN_TRADENUM);
      }      
   }
      
   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、全オーダーの指値と逆指値をセットする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      update_AllOrdersTPSL(global_Symbol, MagicNumberMACDRCI, TP_PIPS, SL_PIPS);
   } 

   //最小利食値FLOORINGが設定されていれば、損切値の更新を試す。
   if(FLOORING >= 0) {
      flooringSL(global_Symbol, MagicNumberMACDRCI, FLOORING, FLOORING_CONTINUE);
   }

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、マジックナンバーをキーとして強制決済をする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      do_ForcedSettlement(MagicNumberMACDRCI, global_Symbol, TP_PIPS, SL_PIPS);
   } 
  
   return(0);	
}	
	


//+------------------------------------------------------------------+
//|15.MACDRCI             　　　　   　　　　　                      |
//+------------------------------------------------------------------+

void entryMACDRCI2(int mMagic) {
/***外部パラメータを戦略別mqhのグローバル変数に代入する***/
   RCIhighLine = G_RCIhighLine;
   RCIlowLine  = G_RCIlowLine;
/****************************************/
   // 戦略別mqhの関数を使用する。
   int mSignal = entryMACDRCI2();
   int ticket_num;

   if( MACDRCItime0 != Time[0] && mSignal == SELL_SIGNAL) { 
      ticket_num = mOrderSend5(global_Symbol,OP_SELL,LOTS,Bid,SLIPPAGE,0.0,0.0,changeMagicToString(mMagic),mMagic,0,LINE_COLOR_SHORT);
      if(ticket_num > 0) {
         MACDRCItime0 = Time[0];
      }
      else if(ticket_num == ERROR_ORDERSEND) {
         printf( "[%d]エラー 売り発注の失敗::%d" , __LINE__ , ticket_num);
      } 
   }

   if( MACDRCItime0 != Time[0] && mSignal == BUY_SIGNAL) {
      ticket_num = mOrderSend5(global_Symbol,OP_BUY,LOTS,Ask,SLIPPAGE,0.0,0.0,changeMagicToString(mMagic),mMagic,0, LINE_COLOR_LONG);	
      if(ticket_num > 0) {
         MACDRCItime0 = Time[0];
      }
      else if(ticket_num == ERROR_ORDERSEND) {
         printf( "[%d]エラー 買い発注の失敗::%d" , __LINE__ , ticket_num);
      } 
   }

}
   





//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|   共通関数　　　                                                 |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|   定時メール送信                                                 |
//+------------------------------------------------------------------+	
void SendMailOrg(int mailtime1, int mailtime2)						
{	
   int j;
   int mMinute = Minute();
   double PBwin = 0.0;
   double Otherswin = 0.0;
  
   double PBlose = 0.0;
   double Otherslose = 0.0;

   int    bufMagicNumber = 0;

   double PBRate = 0.0;
   double OthersRate = 0.0;
   string bufOthers = "";

   if( ((mMinute  == mailtime1) || (mMinute  == mailtime2)) && (mMailFlag  == true) ){						
      string strSubject = "";
      string strBody    = "";
      double mWin = 0.0;        //勝ち数
      double mLose = 0.0; 	  //負け数
      double mDraw = 0.0;	  //引き分け数
      double mPFWin = 0.0;      //実現利益。プロフィットファクタ計算用。
      double mPFLose = 0.0;	  //実現損失。プロフィットファクタ計算用。
      double mPF = 0.0;	  //プロフィットファクタ。
      double mLoseMax = 0.0;    //最大損失。Ｒ倍数計算用
      datetime doneFlag = 0;         //決済フラグ
      double latentLoss = 0.0;  //含み損
      double latentProf = 0.0;  //含み益	   				
      double mProfLoss = 0.0;   //実現損益。

      MqlDateTime server;
      MqlDateTime trade;
      TimeCurrent(server);
   	
      int year  = server.year;  //プログラム実行時の年
      int month = server.mon;   //プログラム実行時の月
      int day   = server.day;   //プログラム実行時の日
	
      int orderType = 0;
      double orderProf = 0.0;

      //
      // 日次損益計算
      // 
      // 実現損益の計算
      for(j = OrdersHistoryTotal() - 1; j >= 0; j--) {
         if(OrderSelect(j, SELECT_BY_POS, MODE_HISTORY) == false) {
            break;
         }
				
         // 決済日時をtradeに格納する。        
         TimeToStruct(OrderCloseTime(), trade);

         // 当日決済取引を処理対象とする。
         if( (trade.year == year) && (trade.mon  == month) && (trade.day  == day)) {	//実行年月日の取引データを集計する。
            orderType = OrderType();
            orderProf = OrderProfit();
            if( (orderType == OP_BUY) || (orderType == OP_SELL) ){  	
               bufMagicNumber = OrderMagicNumber();
               mProfLoss = mProfLoss + orderProf;

               // 利益確定済み
               if(orderProf > 0.0) {
                  // 当日に利益が出た全取引数と利益を計算する。
                  mWin = mWin + 1;		
                  mPFWin = mPFWin + orderProf;	

                  // 戦略別の利益確定取引数を計算する。
                  if(bufMagicNumber == MagicNumberMACDRCI) {
                     PBwin = PBwin + 1;
                  }
                  else  {
                     bufOthers = bufOthers + "--" + IntegerToString(bufMagicNumber);
                     Otherswin = Otherswin + 1;
                  } 	
               }			
               // 損失確定済み
               else if(orderProf < 0.0) {
                  // 当日に損失が出た全取引数と損失を計算する。
                  mLose = mLose + 1;
                  mPFLose = mPFLose + orderProf;

                  // 戦略別の損失確定取引数を計算する。
                  if(bufMagicNumber == MagicNumberMACDRCI) {
                     PBlose = PBlose + 1;
                  }
                  else  { 
                     Otherslose = Otherslose + 1;
                     bufOthers = bufOthers + "--" + IntegerToString(bufMagicNumber);
                  } 
                  
                  // 1取引当たりの最大損失を取得する。
                  if(orderProf < mLoseMax) {
                     mLoseMax = orderProf;
                  }
               }
               // 引き分け
               else {
                  mDraw = mDraw + 1;
               }
            } // if( (orderType == OP_BUY) || (orderType == OP_SELL) ){ 
         }    // if( (trade.year == year) && (trade.mon  == month) && (trade.day  == day)) {
      }       // for(j = OrdersHistoryTotal() - 1; j >= 
   	


      //
      // 計算時点の含み損益計算
      // 
      // 全取引の含み損益の計算	
      latentProf = 0.0;	
      latentLoss = 0.0;
      for(j = OrdersTotal() - 1; j >= 0; j--){						
         if(OrderSelect(j, SELECT_BY_POS, MODE_TRADES) == false) {
            break;
         } 
         doneFlag = OrderCloseTime();				
         if(doneFlag <= 0) {     //オーダーが決済されていない時、含み損益の計算をする。	 
            orderProf = OrderProfit();
            // 評価益
            if(orderProf > 0.0) {
               latentProf = latentProf + orderProf; 
            }
            else if(orderProf < 0.0) {
               latentLoss = latentLoss + orderProf;
            }
            else {
            }			
         } //オーダーが決済されていないとき－終了			
      }

      //
      // 月次損益計算
      // 
      double mWinMonthly       = 0.0; // 当月の全勝ち数
      double mLoseMonthly      = 0.0; // 当月の全負け数
      double mDrawMonthly      = 0.0; // 当月の全引き分け数
      double mProfLossMonthly  = 0.0; // 当月の全実現損益
 
      double PBwinMonthly      = 0.0; // 当月の戦略別勝ち数
      double OtherswinMonthly  = 0.0; // 当月のその他戦略の勝ち数
 
      double PBloseMonthly     = 0.0; // 当月の戦略別敗け数
      double OthersloseMonthly = 0.0; // 当月のその他戦略の敗け数

      double PBRateMonthly     = 0.0; // 当月の戦略別勝率
      double OthersRateMonthly = 0.0; // 当月のその他戦略の勝率
      string bufOthersMonthly = "";
      for(j = OrdersHistoryTotal() - 1; j >= 0; j--){
         if(OrderSelect(j, SELECT_BY_POS, MODE_HISTORY) == false) {
            break;
         }
 
         // 決済日時をtradeに格納する。        
         TimeToStruct(OrderCloseTime(), trade);	

         if( (trade.year == year) && (trade.mon  == month) ) {	//実行年月の取引データを集計する。
            orderType = OrderType();
            orderProf = OrderProfit();
            if( (orderType == OP_BUY) || (orderType == OP_SELL) ){
               // 月次の全決済損益を計算する
               mProfLossMonthly = mProfLossMonthly + orderProf;		

               bufMagicNumber = OrderMagicNumber();
               // 利益確定済み
               if(orderProf > 0.0) {
                  // 当月に利益が出た全取引数を計算する。
                  mWinMonthly  = mWinMonthly  + 1;
                  
                  // 戦略別の利益確定取引数を計算する。
                  if(bufMagicNumber == MagicNumberMACDRCI) {
                     PBwinMonthly = PBwinMonthly + 1;
                  } 
                  else {
                     OtherswinMonthly = OtherswinMonthly + 1;
                  } 	
               }
               // 損失確定済み
               else if(orderProf < 0) {
                  // 当月に損失が出た全取引数を計算する。
                  mLoseMonthly  = mLoseMonthly  + 1;			

                  // 戦略別の利益確定取引数を計算する。
                  if(bufMagicNumber == MagicNumberMACDRCI) {
                     PBloseMonthly = PBloseMonthly + 1;
                  }
                  else  {
                     OthersloseMonthly = OthersloseMonthly + 1;
                  }
               }
               // 引き分け
               else {
                  mDrawMonthly  = mDrawMonthly  + 1;
               }
            } // if( (orderType == OP_BUY) || (orderType == OP_SELL) ){
         }    // if( (trade.year == year) && (trade.mon  == month) ) {	//実行年月の取引データを集計する。
      }	      // for(j = OrdersHistoryTotal() - 1; j >= 0; j--){

      strSubject = MachineName + "：：" + DoubleToStr(Hour(), 0) + "時" + DoubleToStr(Minute(), 0) +"分のお知らせ";
      strBody    = strBody + DoubleToStr(mWin, 0) + "勝" + DoubleToStr(mLose, 0) + "敗" + DoubleToStr(mDraw, 0) + "分" + "\n";			

      //勝率の計算  	
      double mWinLose = 0.0;
      string bufWinLose = "";

      // 全取引の勝率
      if((mWin + mLose + mDraw) != 0) {
         mWinLose = (mWin / (mWin + mLose + mDraw)) * 100;					
      }
      else {
         mWinLose = 0.0;
      }

      // 戦略別の勝率
      if( PBwin + PBlose != 0) {
         PBRate = PBwin / (PBwin + PBlose);
         bufWinLose = bufWinLose + "--PB      ="+ IntegerToString(PBwin + PBlose)+"戦中勝率" + DoubleToStr(PBRate,2) + "\n";			
      }
      else  PBRate = 0.0;

      if( Otherswin + Otherslose != 0) {
         OthersRate = Otherswin / (Otherswin + Otherslose);
	 bufWinLose = bufWinLose + "--その他  ="+ bufOthers + "--" + IntegerToString(Otherswin + Otherslose,0) + "戦中勝率"+DoubleToStr(OthersRate,2) + "\n";
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

      if( PBwinMonthly + PBloseMonthly != 0) {
         PBRateMonthly = PBwinMonthly / (PBwinMonthly + PBloseMonthly);
         bufWinLoseMonthly = bufWinLoseMonthly + "--PB（月次）     ="+ IntegerToString(PBwinMonthly + PBloseMonthly)+"戦中勝率"+DoubleToStr(PBRateMonthly,2) + "\n";			
      }
      else PBRateMonthly = 0.0;

      if( OtherswinMonthly + OthersloseMonthly != 0) { 
         OthersRateMonthly = OtherswinMonthly / (OtherswinMonthly + OthersloseMonthly);
         bufWinLoseMonthly = bufWinLoseMonthly + "--その他（月次）="+ bufOthersMonthly + "--" + IntegerToString(Otherswin + OthersloseMonthly)+"戦中勝率"+DoubleToStr(OthersRateMonthly,2) + "\n";
      }
      else  OthersRateMonthly = 0.0;


      //プロフィットファクターの計算
      if(mPFLose != 0) {
         mPF = mPFWin / (-1* mPFLose);					
      }
      else {
         mPF = 99.99;
      }

      strBody    = IntegerToString(year) + "年" + IntegerToString(month) + "月" + IntegerToString(day) + "日" + "\n";
      strBody    = strBody + "決済損益(月次)＝" + DoubleToStr(mProfLossMonthly, 5) + "\n";
      strBody    = strBody + "勝率（月次）= " + DoubleToStr( mWinLoseMonthly,2) + "\n";
      strBody    = strBody + bufWinLoseMonthly;
      strBody = strBody + "------------------------" + "\n";

      strBody    = strBody + "決済損益(日次)＝" + DoubleToStr(mProfLoss, 5) + "\n";		
      strBody    = strBody + "勝率（日次）= " + DoubleToStr( mWinLose,2) + "\n";
      strBody    = strBody + bufWinLose;
	
      strBody = strBody + "------------------------" + "\n";
      strBody = strBody + "PF（目標2.0以上) = " + DoubleToStr(mPF,2) + "\n";
      strBody = strBody + "含み損 = " + DoubleToStr(latentLoss ,2) + "\n";	   				
      strBody = strBody + "含み益 = " + DoubleToStr(latentProf ,2) + "\n";
      strBody = strBody + "------------------------" + "\n";
      strBody = strBody + "========================" + "\n";					
      strBody = strBody + readOpenOders();			

      //メールを送信する。
      SendMail(strSubject , strBody);
      mMailFlag = false;
   }	
   else if( (Minute() != mailtime1) && (Minute() != mailtime2) ){	
      mMailFlag = true;
   }	
} 	


//+------------------------------------------------------------------+
//| マジックナンバー（数値）を戦略名（文字列）に変換する　　　                     　　　　　      |
//+------------------------------------------------------------------+
string changeMagicToString(int mag) {
   string strBuf = "";
if(mag == MagicNumberMACDRCI) {
         strBuf = g_StratName25;
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

