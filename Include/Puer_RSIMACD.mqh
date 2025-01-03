//#property strict	
//+------------------------------------------------------------------+	
//|  　　　　　　　　　　　　　　　　　　　　　　　　　　　                              |
//|  Copyright (c) 2016 トラの親 All rights reserved.                |	
//|                                                                  |
//+------------------------------------------------------------------+	
//+------------------------------------------------------------------+	
//| ヘッダーファイル読込                                             |	
//+------------------------------------------------------------------+	
#include <Tigris_COMMON.mqh>
#include <Tigris_GLOBALS.mqh>

//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	



//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
/*
double ENTRYRSI_highLine = 35.0; //RSIのハイライン。
double ENTRYRSI_lowLine  = 15.0; //RSIのロウライン。	
*/
//+------------------------------------------------------------------+
//|14.RSIMACD                                        　　　　　      |
//+------------------------------------------------------------------+
//RSIとMACDを使った売買フラグ判定
int entryRSIMACD() {
	int mSignal  = NO_SIGNAL;  // 戻り値
	int ticket_num = 0;
   bool mFlag = false;
   double sl = 0.0;
   double tp = 0.0;

	double RSI_9  = NormalizeDouble(iRSI(global_Symbol, 0,  9, PRICE_CLOSE,1), global_Digits);
	double RSI_26 = NormalizeDouble(iRSI(global_Symbol, 0, 26, PRICE_CLOSE,1), global_Digits);
	double RSI_52 = NormalizeDouble(iRSI(global_Symbol, 0, 52, PRICE_CLOSE,1), global_Digits);
	double MACD_1   = NormalizeDouble(iMACD(global_Symbol,0,12,26,9,0,0,1), global_Digits*2);
	double MACD_2   = NormalizeDouble(iMACD(global_Symbol,0,12,26,9,0,0,2), global_Digits*2);
	double Signal_1 = NormalizeDouble(iMACD(global_Symbol,0,12,26,9,0,1,1), global_Digits*2);
	double Signal_2 = NormalizeDouble(iMACD(global_Symbol,0,12,26,9,0,1,2), global_Digits*2);

   int BuySellflag = 0; // ロングとショート発生すれば＋１する。ロングとショートの両方を満たしていれば２になる。
   
  /*
printf( "[%d]RSIMACD RSI_9=%s  RSI_26=%s  RSI_52=%s ENTRYRSI_lowLine=%s" , __LINE__,
DoubleToStr(RSI_9, global_Digits),
DoubleToStr(RSI_26, global_Digits),
DoubleToStr(RSI_52, global_Digits),
DoubleToStr(ENTRYRSI_lowLine, global_Digits)
);  
*/


	//3点がlowLineより下で売られ過ぎ、
	//かつ、上からRSI_9、RSI_26、RSI52の順であり、
	//かつ、MACDがゴールデンクロス状態（MACDが0より大＋シグナルが下）
	//以上を満たした時に買い
	if(
	   (RSI_9 < ENTRYRSI_lowLine  && RSI_26 < ENTRYRSI_lowLine  && RSI_52 < ENTRYRSI_lowLine )  //3点がlowLineより下
	      &&
    	(RSI_9 > RSI_26 && RSI_26 > RSI_52 )   //上からRSI_9、RSI_26、RSI52の順
    	   &&
      (MACD_1 > 0.0 && MACD_1 > Signal_1 )   //MACDがゴールデンクロス状態（MACDが0より大＋シグナルが下）
     ) { 
			mSignal = BUY_SIGNAL;
			BuySellflag++;
	}
	//3点がhighLineより上で買われ過ぎ、
	//かつ、上からRSI_52、RSI_26、RSI9の順であり、
	//かつ、MACDがデッドクロス状態（MACDが0より小＋シグナルが上）
	//以上を満たした時に売り
	if(
    		( RSI_9 > ENTRYRSI_highLine && RSI_26 > ENTRYRSI_highLine && RSI_52 > ENTRYRSI_highLine)  ////3点がhighLineより上
    		   &&
    		( RSI_9 < RSI_26 && RSI_26 < RSI_52 )   //上からRSI_52、RSI_26、RSI9の順
	    	   &&
	    	( MACD_1 < 0.0 && MACD_1 < Signal_1 ) ){//MACDがデッドクロス状態（MACDが0より小＋シグナルが上）
			mSignal = SELL_SIGNAL;
			BuySellflag++;
	}
  
  // BuySellflagが2以上で複数のシグナルが発生している場合は、基準となる値ENTRYRSI_lowLine、ENTRYRSI_highLineとRSIとの
  // 距離の絶対値合計が小さい方を採用(＝基準から離れている方を却下)する。
  if(BuySellflag >= 2) {
     double BuyDistance = MathAbs(RSI_9 - ENTRYRSI_lowLine) 
                          + MathAbs(RSI_26 - ENTRYRSI_lowLine) 
                          + MathAbs(RSI_52 - ENTRYRSI_lowLine)  ;
     double SellDistance = MathAbs(RSI_9 - ENTRYRSI_highLine) 
                          + MathAbs(RSI_26 - ENTRYRSI_highLine) 
                          + MathAbs(RSI_52 - ENTRYRSI_highLine)  ;
     if(NormalizeDouble(BuyDistance, global_Digits) <= NormalizeDouble(SellDistance, global_Digits) ) {
        mSignal = BUY_SIGNAL;
/*        printf( "[%d]RSIMACD 買いの勝ち　BuyDistance=%s  SellDistance=%s" , __LINE__,
                  DoubleToStr(BuyDistance, global_Digits),
                  DoubleToStr(SellDistance, global_Digits));*/
     }
     else {
        mSignal = SELL_SIGNAL;
/*        printf( "[%d]RSIMACD 売りの勝ち　BuyDistance=%s  SellDistance=%s" , __LINE__,
                  DoubleToStr(BuyDistance, global_Digits),
                  DoubleToStr(SellDistance, global_Digits));*/
     }
  }
  return mSignal;
}


