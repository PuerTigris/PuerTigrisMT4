// 20220613ZZのみのEAとして、新規作成
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
#include <Puer_ZZ.mqh>
//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
extern int MagicNumberZZ       = 90000024;   


extern string ZZParameters = "---ZZのパラメータ---";
extern int G_ZigzagDepth = 12;
extern int G_ZigzagDeviation = 5;
extern int G_ZigzagBackstep = 3;
extern int G_ZigzagTradePattern = 1;


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
datetime zigtime0 = 0;     
// ZZTrailingの連続実行を避けるための変数。
datetime ZZtrailingtime0 = 0;
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

   //bool flag_calc_TradingLines = calc_TradingLines(global_Symbol, TIME_FRAME_MAXMIN, SHIFT_SIZE_MAXMIN, g_past_max, g_past_maxTime, g_past_min, g_past_minTime, g_past_width, g_long_Min, g_long_Max, g_short_Min, g_short_Max);
   bool flag_calc_TradingLines = calc_TradingLines(global_Symbol, 
                                                   TIME_FRAME_MAXMIN, 
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
   printf( "[%d]エラーZZ トレーディングラインの計算失敗" , __LINE__);
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

   ShowTestMsg = false;
   /*
   // UpdateMinutes分間隔で、以下の処理を実行する。
   if(TimeCurrent() - CONTROLALLtime0 >= PING_WEIGHT_MINS * 60) { // 
      CONTROLALLtime0 = TimeCurrent();
   }
   else {
      return ERROR;
   }	
   */
   
   // ショートする時の価格BIDが過去最大値を超えた場合は、トレンドが大きく変わったと判断して、トレーディングラインを更新。
   tmpBID = Bid; 
   if(g_past_max > 0.0 && NormalizeDouble(g_past_max, global_Digits) < NormalizeDouble(tmpBID, global_Digits)) {  
      global_flag_StopTradeUpper = true;
      update_TradingLines(global_Symbol, TIME_FRAME_MAXMIN, SHIFT_SIZE_MAXMIN);
   }

   // ロングする時の価格ASKが過去最小値を下回った場合は、トレンドが大きく変わったと判断して、トレーディングラインを更新。
   tmpASK = Ask;
   if(g_past_min > 0.0 && NormalizeDouble(g_past_min, global_Digits) > NormalizeDouble(tmpASK, global_Digits)) {  
      update_TradingLines(global_Symbol, TIME_FRAME_MAXMIN, SHIFT_SIZE_MAXMIN);       
   }
   
   // 実行時点で未決済取引をグローバル変数に読み出す。
   // read_OpenTrades(MagicNumberZZ);
   
/*   
   // ask,bidの両方で、いづれかの取引の建値との差異が、パラメータ20pips*パラメータ許容誤差10%以内なら、本体の売買関数はジャンプ。
   // 強制決済などは実行。
   double allawableDiff_PIPS = NormalizeDouble(ENTRY_WIDTH_PIPS * ALLOWABLE_DIFF_PER / 100.0, global_Digits); // 許容誤差。PIPS単位。
   bool flagCheckPrice;
   flagCheckPrice = isExistingNearOpenPrices(MagicNumberZZ, allawableDiff_PIPS, tmpBID, tmpASK); // Bid、Ask共に近い建値のオープン中の取引があれば、true.
   if(flagCheckPrice == false) {
      // ZZを使った実取引
      entryZZ(MagicNumberZZ, g_StratName24);
   }
*/

   if(zigtime0 != Time[0]) {
      entryZZ(MagicNumberZZ, g_StratName24);
   } 

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、全オーダーの指値と逆指値をセットする。
   // ZZは、TP_PIPSやSL_PIPSによる強制決済をしないことを推奨	
   if(TP_PIPS > 0 || SL_PIPS > 0) {
      update_AllOrdersTPSL(global_Symbol, MagicNumberZZ, TP_PIPS, SL_PIPS);
/*      printf( "[%d]ZZ　このEAはTP_PIPS=%s, SL_PIPS=%sをともに使わず、両方0以下にすることを推奨", __LINE__,
               DoubleToStr(TP_PIPS, global_Digits), 
               DoubleToStr(SL_PIPS, global_Digits)
      ); 
      */
   } 
    
   // update_AllOrdersTPSLの代わりに、損切値を設定する。  
   // 損切値の候補がより有利であれば、上書きする。
   // 損切値の候補は、
   // 2つ前の谷より直前の谷が高ければ、ロングのストップを直前の谷に更新する。
   // 2つ前の山より直前の山が低ければ、ショートのストップを直前の山に更新する。
   update_AllOrdersSLZigzag(MagicNumberZZ, global_Symbol, g_StratName24);  


   //最小利食値FLOORINGが設定されていれば、損切値の更新を試す。
   if(FLOORING >= 0) {
      flooringSL(global_Symbol, MagicNumberZZ, FLOORING, FLOORING_CONTINUE);
   }

   if(ZZtrailingtime0 != Time[0]) {
      ZZTrailing(global_Symbol,
                   MagicNumberZZ   // flooring設定をする約定のマジックナンバー
                  );
      ZZtrailingtime0 = Time[0];
   }                     
                     
   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、マジックナンバーをキーとして強制決済をする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      do_ForcedSettlement(MagicNumberZZ, global_Symbol, TP_PIPS, SL_PIPS);
/*      printf( "[%d]ZZ　このEAはTP_PIPS=%s, SL_PIPS=%sをともに使わず、両方0以下にすることを推奨", __LINE__,
               DoubleToStr(TP_PIPS, global_Digits), 
               DoubleToStr(SL_PIPS, global_Digits)
      ); */
   } 

   return(0);	
}	
	




//+------------------------------------------------------------------+
//| ZZ     PuerTigris026.mq4から抜粋                  　　　　       |
//+------------------------------------------------------------------+
bool entryZZ(int mMagic, string mStrategy){
/***外部パラメータを戦略別mqhのグローバル変数に代入する***/
   ZigzagDepth     = G_ZigzagDepth;
   ZigzagDeviation = G_ZigzagDeviation;
   ZigzagBackstep  = G_ZigzagBackstep;
   ZigzagTradePattern = G_ZigzagTradePattern;
/****************************************/
   // 戦略別mqhの関数を使用する。
   int mSignal = entryZZ_RT(ZigzagTradePattern);
   bool mFlag = false;
   double sl = 0.0;
   double tp = 0.0;
   int ticket_num = 0;

  // double mMarketinfoMODE_ASK;
  // double mMarketinfoMODE_BID;

   // 4時間足の傾きでシグナルを見直す。
   if(mSignal == BUY_SIGNAL || mSignal == SELL_SIGNAL) {

      int trend = get_Trend_EMA_PERIODH4(global_Symbol, 0);
      if(mSignal == BUY_SIGNAL && trend == DownTrend) {
//printf( "[%d] get_Trend_EMA_PERIODH4で傾きを検証して、買いシグナルを廃止" , __LINE__);      
         mSignal =NO_SIGNAL;
      }
      else if(mSignal == SELL_SIGNAL && trend == UpTrend) {
//printf( "[%d] get_Trend_EMA_PERIODH4で傾きを検証して、売りシグナルを廃止" , __LINE__);      
         mSignal =NO_SIGNAL;         
      }
   }
      
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
   double mMarketinfoMODE_BID = MarketInfo(global_Symbol,MODE_BID);     
   double mMarketinfoMODE_ASK = MarketInfo(global_Symbol,MODE_ASK);   
   if(mSignal == BUY_SIGNAL || mSignal == SELL_SIGNAL) {
      update_TradingLines(global_Symbol, TIME_FRAME_MAXMIN, SHIFT_SIZE_MAXMIN);
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
   // トレーディングラインとENTRY_WIDTH_PIPSを使って、発注予定値が条件を満たすかどうかを判断する。
   // 発注不可の値であれば、シグナルをNO_SIGNALに変更する。
   bool flag_is_TradablePrice;
   if( mSignal == BUY_SIGNAL) {
      mMarketinfoMODE_ASK = MarketInfo(global_Symbol,MODE_ASK);   
      flag_is_TradablePrice = 
         is_TradablePrice(mMagic,
                                     BUY_SIGNAL,
                                     long_Max,
                                     long_Min,
                                     ENTRY_WIDTH_PIPS,     // 何PIPSの間隔をあけるか
                                     mMarketinfoMODE_ASK); // 発注予定値
      if(flag_is_TradablePrice == false) {
printf( "[%d]PB ロングシグナル取り消し" , __LINE__);
         mSignal = NO_SIGNAL;
      }
   }
   else if( mSignal == SELL_SIGNAL) {
      mMarketinfoMODE_BID = MarketInfo(global_Symbol,MODE_BID);
      flag_is_TradablePrice = 
         is_TradablePrice(mMagic,
                                     SELL_SIGNAL,
                                     short_Max,
                                     short_Min,
                                     ENTRY_WIDTH_PIPS,     // 何PIPSの間隔をあけるか
                                     mMarketinfoMODE_BID); // 発注予定値
      if(flag_is_TradablePrice == false) {

         mSignal = NO_SIGNAL;
      }
   }

   if( mSignal == BUY_SIGNAL && zigtime0 != Time[0]) {
      if(TP_PIPS > 0.0) {
         tp = mMarketinfoMODE_ASK + NormalizeDouble(change_PiPS2Point(TP_PIPS), global_Digits); // 利確の候補
      }
      else {
         tp = 0.0;
      }
      if(SL_PIPS > 0.0) {
         sl = mMarketinfoMODE_ASK - NormalizeDouble(change_PiPS2Point(SL_PIPS), global_Digits); // 損切の候補 
      }
      else {
         sl = 0.0;
      }

      ticket_num = mOrderSend5(global_Symbol,OP_BUY,LOTS,mMarketinfoMODE_ASK,SLIPPAGE, sl, tp,changeMagicToString(mMagic),mMagic,0, LINE_COLOR_LONG);	

      if(ticket_num > 0){
/*
printf( "[%d]ZZ 取引時間の更新　zigtime0=>%d< から　Time[0]=>%d<　へ更新" , __LINE__ , 
         zigtime0, Time[0]
);
if(zigtime0 == Time[0]) {
printf( "[%d]ZZ 同じ値 　取引時間の更新　zigtime0=>%d< から　Time[0]=>%d<　へ更新" , __LINE__ , 
         zigtime0, Time[0]
); 
}
else {
printf( "[%d]ZZ 異なる値取引時間の更新　zigtime0=>%d< から　Time[0]=>%d<　へ更新" , __LINE__ , 
         zigtime0, Time[0]
); 
}
*/
         zigtime0 = Time[0];
      }
      else if(ticket_num == ERROR_ORDERSEND) {
         printf( "[%d]エラー 買い発注の失敗::%d" , __LINE__ , ticket_num);
      } 
   }
   else if(mSignal == SELL_SIGNAL  && zigtime0 != Time[0]) {
      if(TP_PIPS > 0.0) {
         tp = mMarketinfoMODE_BID - NormalizeDouble(change_PiPS2Point(TP_PIPS), global_Digits); // 利確の候補
      }
      else {
         tp = 0.0;
      }
      if(SL_PIPS > 0.0) {
         sl = mMarketinfoMODE_BID + NormalizeDouble(change_PiPS2Point(SL_PIPS), global_Digits); // 損切の候補 
      }
      else {
         sl = 0.0;
      }
      ticket_num = mOrderSend5(global_Symbol,OP_SELL,LOTS,mMarketinfoMODE_BID,SLIPPAGE,sl, tp,changeMagicToString(mMagic),mMagic,0,LINE_COLOR_SHORT);

      if(ticket_num > 0) {
/*
printf( "[%d]ZZ 取引時間の更新　zigtime0=>%d< から　Time[0]=>%d<　へ更新" , __LINE__ , 
         zigtime0, Time[0]
); 
if(zigtime0 == Time[0]) {
printf( "[%d]ZZ 同じ値 　取引時間の更新　zigtime0=>%d< から　Time[0]=>%d<　へ更新" , __LINE__ , 
         zigtime0, Time[0]
); 
}
else {
printf( "[%d]ZZ 異なる値取引時間の更新　zigtime0=>%d< から　Time[0]=>%d<　へ更新" , __LINE__ , 
         zigtime0, Time[0]
); 
}
*/
         zigtime0 = Time[0];
      }
      else if(ticket_num == ERROR_ORDERSEND) {
         printf( "[%d]エラー 売り発注の失敗::%d" , __LINE__ , ticket_num);
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
//| オープン中のオーダーを列挙する                   　　　　　      |
//+------------------------------------------------------------------+
 string readOpenOders() {	
	string strBuf ="";
	int orderType = 0;

	for(int j = OrdersTotal() - 1; j >= 0; j--){					
      		if(OrderSelect(j, SELECT_BY_POS, MODE_TRADES) == false) break;				

		datetime doneFlag = OrderCloseTime();				
	  	if(doneFlag == 0) {     //オーダーが決済されていない時、その内容をバッファに追加する。				
     		        strBuf = strBuf + "番号＝" + DoubleToStr(j, 0) + "\n";//番号				
			strBuf = strBuf + "通貨ペア＝" + OrderSymbol() + "\n";//通貨ペア			
			//売買区分			
			orderType = OrderType();
			
                        if(orderType == OP_BUY) strBuf = strBuf + "売買区分＝買" + "\n";			
			else if(orderType == OP_SELL) strBuf = strBuf + "売買区分＝売" + "\n";		
			else strBuf = strBuf + "売買区分＝" +  DoubleToStr(orderType, 0) + "\n";
                        
                        strBuf = strBuf + "マジックナンバー = " + IntegerToString(OrderMagicNumber()) + "(" + changeMagicToString(OrderMagicNumber()) + ")" + "\n";				
 			strBuf = strBuf + "約定値＝" +  DoubleToStr(OrderOpenPrice(),5) + "\n";//約定値			
			strBuf = strBuf + "約定数＝" +  DoubleToStr(OrderLots(),2) + "\n";//約定数			
			strBuf = strBuf + "約定時間＝" + TimeToStr(OrderOpenTime(), TIME_SECONDS) + "\n";//約定時間			
			strBuf = strBuf + "含み損益＝" +  DoubleToStr(OrderProfit(),5) + "\n";//含み損益			
			

			strBuf = strBuf + "========================" + "\n";			
		}				
	}
	return strBuf;
}		


//+------------------------------------------------------------------+
//|   定時メール送信                                                 |
//+------------------------------------------------------------------+	
void SendMailOrg(int mailtime1, int mailtime2)						
{	
   int j;
   int mMinute = Minute();
   double ZZwin = 0.0;
   double Otherswin = 0.0;
  
   double ZZlose = 0.0;
   double Otherslose = 0.0;

   int    bufMagicNumber = 0;

   double ZZRate = 0.0;
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
                  if(bufMagicNumber == MagicNumberZZ) {
                     ZZwin = ZZwin + 1;
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
                  if(bufMagicNumber == MagicNumberZZ) {
                     ZZlose = ZZlose + 1;
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
 
      double ZZwinMonthly      = 0.0; // 当月の戦略別勝ち数
      double OtherswinMonthly  = 0.0; // 当月のその他戦略の勝ち数
 
      double ZZloseMonthly     = 0.0; // 当月の戦略別敗け数
      double OthersloseMonthly = 0.0; // 当月のその他戦略の敗け数

      double ZZRateMonthly     = 0.0; // 当月の戦略別勝率
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
                  if(bufMagicNumber == MagicNumberZZ) {
                     ZZwinMonthly = ZZwinMonthly + 1;
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
                  if(bufMagicNumber == MagicNumberZZ) {
                     ZZloseMonthly = ZZloseMonthly + 1;
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
      if( ZZwin + ZZlose != 0) {
         ZZRate = ZZwin / (ZZwin + ZZlose);
         bufWinLose = bufWinLose + "--ZZ      ="+ IntegerToString(ZZwin + ZZlose)+"戦中勝率" + DoubleToStr(ZZRate,2) + "\n";			
      }
      else  ZZRate = 0.0;

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

      if( ZZwinMonthly + ZZloseMonthly != 0) {
         ZZRateMonthly = ZZwinMonthly / (ZZwinMonthly + ZZloseMonthly);
         bufWinLoseMonthly = bufWinLoseMonthly + "--ZZ（月次）     ="+ IntegerToString(ZZwinMonthly + ZZloseMonthly)+"戦中勝率"+DoubleToStr(ZZRateMonthly,2) + "\n";			
      }
      else ZZRateMonthly = 0.0;

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
if(mag == MagicNumberZZ) {
         strBuf = g_StratName25;
   }
   else { 
         strBuf = "MN" + IntegerToString(mag, 10);
   } 
   return strBuf;
}

//
//ファイルに文字列を書き込む
//
int mFileWrite(string mFileName, string mWrittenData) {
  int handle;

  //ファイルは terminal_directory\experts\files フォルダ（テストの場合は terminal_directory\tester\files）
  //または、そのサブフォルダにあるものだけ、開くことができます。
  handle=FileOpen(mFileName, FILE_TXT | FILE_WRITE, ';'); 
  
  if(handle <= 0) return handle;

/*【参考】文字列をカンマで分割する
  string sep=",";               // 区切り文字 
  ushort u_sep;                 // 区切り文字のコード 
  string result[];              // 分割された文字列を受け取る配列 
  int sepNum                    // 分割された文字列の個数

  //--- 区切り文字のコードを取得する 
  u_sep = StringGetCharacter(sep,0);
 
  //--- 文字列を部分文字列に分ける 
  sepNum = StringSplit(to_split,u_sep,result); 
*/

  if(handle>0)
    {
     FileWrite(handle, mWrittenData);
     FileClose(handle);
    }
    return 0;
}


bool checkExternalParam() {
   // 現在は、該当する処理無し   
   return true;
}


// 取引しようとしている価格が、買い又は売り可能な範囲内にあれば、trueを返す。それ以外は、falseを返す。
bool judge_Tradable_Price(int mBuySell,  // BUY_SIGNAL, SELL_SIGNAL
                          double mPrice  // 取引しようとしている価格
                          ) {
   bool flag_calc_TradingLines = calc_TradingLines(global_Symbol,  //　通貨ペア
                                            TIME_FRAME_MAXMIN,  // 計算に使う時間軸
                                            SHIFT_SIZE_MAXMIN,    // 計算対象にするシフト数
                                            g_past_max,       // 出力：過去の最高値
                                            g_past_maxTime,   // 出力：過去の最高値の時間
                                            g_past_min,       // 出力：過去の最安値
                                            g_past_minTime,   // 出力：過去の最安値の時間
                                            g_past_width,     // 出力：過去値幅。past_max - past_min
                                            g_long_Min,       // 出力：ロング取引を許可する最小値
                                            g_long_Max,       // 出力：ロング取引を許可する最大値
                                            g_short_Min,      // 出力：ショート取引を許可する最小値
                                            g_short_Max       // 出力：ショート取引を許可する最大値
                                            );
                          
   if(flag_calc_TradingLines == false) {
      return false;
   }
   
   if(mBuySell == BUY_SIGNAL) {
      if(g_long_Min  > 0.0 && g_long_Max  > 0.0 && NormalizeDouble(mPrice, global_Digits) >= NormalizeDouble(g_long_Min, global_Digits)  && NormalizeDouble(mPrice, global_Digits) <= NormalizeDouble(g_long_Max, global_Digits) ) {
         return true;
      }
   }
   else if(mBuySell == SELL_SIGNAL) {
      if(g_short_Min > 0.0 && g_short_Max > 0.0 && NormalizeDouble(mPrice, global_Digits) >= NormalizeDouble(g_short_Min, global_Digits) && NormalizeDouble(mPrice, global_Digits) <= NormalizeDouble(g_short_Max, global_Digits) ) {
            return true;
      }
   }
   return false;
}




