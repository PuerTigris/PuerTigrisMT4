//#property strict	
//+------------------------------------------------------------------+	
//|  PuerTigrisのorderByCORREL_TIME部品                              |
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
double RCIhighLine =  0.5;//
double RCIlowLine  = -0.3;//
*/
//+------------------------------------------------------------------+
//|   No.15 MACDRCI                                                  |
//+------------------------------------------------------------------+  
int entryMACDRCI2() {
   int mSignal = NO_SIGNAL;
   int BuySellflag = 0; // ロングとショート発生すれば＋１する。ロングとショートの両方を満たしていれば２になる。
   
   if(get_Trend_RSIandCCI(global_Period) == NoTrend) {
      return NO_SIGNAL;
   }

   double MACD_1   = NormalizeDouble(iMACD(global_Symbol,0,12,26,9,0,0,1), global_Digits*2);
   double Signal_1 = NormalizeDouble(iMACD(global_Symbol,0,12,26,9,0,1,1), global_Digits*2);
   double MACD_2   = NormalizeDouble(iMACD(global_Symbol,0,12,26,9,0,0,2), global_Digits*2);
   double Signal_2 = NormalizeDouble(iMACD(global_Symbol,0,12,26,9,0,1,2), global_Digits*2);
   double RCI_9_1  = NormalizeDouble(mRCI2(global_Symbol, 0, 9,  1), global_Digits*2); // RCIの変動範囲は-100～100
   double RCI_9_2  = NormalizeDouble(mRCI2(global_Symbol, 0, 9,  2), global_Digits*2); // RCIの変動範囲は-100～100
   double RCI_26   = NormalizeDouble(mRCI2(global_Symbol, 0, 26, 1), global_Digits*2); // RCIの変動範囲は-100～100
   double RCI_52   = NormalizeDouble(mRCI2(global_Symbol, 0, 52, 1), global_Digits*2); // RCIの変動範囲は-100～100
/*
printf( "[%d]MACDRCI RCI_9_1=%s RCI_9_2=%s RCI_26=%s RCI_52=%s  RCIhighLine=%s  RCIlowLine=%s" , __LINE__,
   DoubleToStr(RCI_9_1, global_Digits),
   DoubleToStr(RCI_9_2, global_Digits),
   DoubleToStr(RCI_26, global_Digits),   
   DoubleToStr(RCI_52, global_Digits),
   DoubleToStr(RCIhighLine, global_Digits),
   DoubleToStr(RCIlowLine, global_Digits)
   
);
*/
   //RCI中期(26)長期(52)の2点がRCIhighLineより上で買われ過ぎ、短期(9)がRCIhighLineを上から下へ
   //かつ、MACDがデッドクロス状態（MACDが0より小＋シグナルが上）
   //以上を満たした時に売り
   if((RCI_26  > RCIhighLine && RCI_52 > RCIhighLine) &&
      (RCI_9_2 > RCIhighLine && RCI_9_1 < RCIhighLine )  ) {   
         mSignal = SELL_SIGNAL;
         BuySellflag++;
   }

   //RCI3本がすべてRCIlowLineより上で売られすぎではなく、すべて下降中ならば買い 

   //RCI3本がすべてRCIhighLineより下で買われすぎではなく、すべて上昇中ならば買い
/*
printf( "[%d]MACDRCI ロング条件スタート" , __LINE__);
if(RCI_26 < RCIlowLine  && RCI_52 < RCIlowLine ) {
printf( "[%d]MACDRCI ロング条件１達成" , __LINE__);
}
if(RCI_9_2 < RCIlowLine && RCI_9_1 > RCIlowLine) {
printf( "[%d]MACDRCI 　　　ロング条件２達成" , __LINE__);
}
else{
printf( "[%d]MACDRCI 　　　RCI_9_2=%s  RCI_9_2=%s Lowline=%s" , __LINE__,
DoubleToStr(RCI_9_2, global_Digits),
DoubleToStr(RCI_9_2, global_Digits),
DoubleToStr(RCIlowLine, global_Digits)
);
}
*/

   //RCI中期(26)長期(52)の2点がRCIlowLineより下で売られ過ぎ、短期(9)がRCIlowLineを下から上へ
   //かつ、MACDがゴールデンクロス状態（MACDが0より大＋シグナルが下）
   //以上を満たした時に買い
   if((RCI_26 < RCIlowLine  && RCI_52 < RCIlowLine) &&
      (RCI_9_2 < RCIlowLine && RCI_9_1 > RCIlowLine )  ) {
         BuySellflag++;      
         mSignal = BUY_SIGNAL;
   }
   
  // BuySellflagが2以上で複数のシグナルが発生している場合は、基準となるRCIlowLine、RCIhighLineとRCI_9との
  // 距離の絶対値合計が小さい方を採用(＝基準から離れている方を却下)する。
   if(BuySellflag >= 2) {
     double BuyDistance = MathAbs(RCI_9_2 - RCIlowLine) 
                          + MathAbs(RCI_9_1 - RCIlowLine);
     double SellDistance = MathAbs(RCI_9_2 - ENTRYRSI_highLine) 
                          + MathAbs(RCI_9_1 - ENTRYRSI_highLine);
     if(NormalizeDouble(BuyDistance, global_Digits) <= NormalizeDouble(SellDistance, global_Digits) ) {
        mSignal = BUY_SIGNAL;
     }
     else {
        mSignal = SELL_SIGNAL;
     }   
   }
   return mSignal;
}
