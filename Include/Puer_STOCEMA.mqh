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
int STOCEMAHigh = 10;       //ストキャスティクスのHighライン	
int STOCEMALow  = 55;       //ストキャスティクスのLowライン							
*/


//+------------------------------------------------------------------+
//|07.EMA                                              　　　　      |
//+------------------------------------------------------------------+
int entryRangeSTOCEMA(){
   if(STOCEMAHigh < STOCEMALow) return NO_SIGNAL;
   //レンジ外の場合（＝トレンドが発生している時）は何もしない。
   if(get_Trend_RSIandCCI(global_Period) != 0 ) return NO_SIGNAL;

   int mSignal = NO_SIGNAL;
   bool mFlag = false;
   double sl = 0.0;
   double tp = 0.0;
   int ticket_num = 0;

   double EMA_10    = iMA(global_Symbol,0,10 ,0,MODE_EMA,PRICE_CLOSE,1);
   double EMA_50    = iMA(global_Symbol,0,50 ,0,MODE_EMA,PRICE_CLOSE,1);
   double EMA_200   = iMA(global_Symbol,0,200,0,MODE_EMA,PRICE_CLOSE,1);
   double Stoc_MAIN = iStochastic(global_Symbol, 0, 5, 3, 3, 0, 0, MODE_MAIN, 1);
   //〔ロングエントリーの場合〕
   //
   //１．上からEMA10、50、200の順番であること。
   //２．Stchastic Oscillatorが20のラインを上抜いたのを確認すること。
   //３．レートがEMA２００を上回っていること。

   if(NormalizeDouble(EMA_10, global_Digits) > NormalizeDouble(EMA_50, global_Digits) 
      && NormalizeDouble(EMA_50, global_Digits) > NormalizeDouble(EMA_200, global_Digits)
      && NormalizeDouble(EMA_200, global_Digits) > 0.0) {
      if((NormalizeDouble(Stoc_MAIN, global_Digits) > NormalizeDouble(STOCEMALow, global_Digits)  && iStochastic(global_Symbol, 0, 5, 3, 3, 0, 0, MODE_MAIN, 2) < STOCEMALow) &&
         NormalizeDouble(Close[1], global_Digits) > NormalizeDouble(EMA_200, global_Digits) ) {
         mSignal = BUY_SIGNAL;
      }
   }

   //〔ショートエントリーの場合〕
   //ショートエントリーは、ロングエントリーと逆で
   //１．上からEMA２００、５０、１０の順番であること。
   //２．Stchastic Oscillatorが８０のラインを下抜いたのを確認すること。
   //３．レートがEMA２００を下回っていること。
   if(NormalizeDouble(EMA_10, global_Digits) < NormalizeDouble(EMA_50, global_Digits) 
      && NormalizeDouble(EMA_50, global_Digits) < NormalizeDouble(EMA_200, global_Digits)
      && NormalizeDouble(EMA_10, global_Digits)> 0.0 ) {
      if((NormalizeDouble(Stoc_MAIN, global_Digits) < NormalizeDouble(STOCEMAHigh, global_Digits)  && iStochastic(global_Symbol, 0, 5, 3, 3, 0, 0, MODE_MAIN, 2) > STOCEMAHigh) &&
         NormalizeDouble(Close[1], global_Digits) < NormalizeDouble(EMA_200, global_Digits) ) {
         mSignal = SELL_SIGNAL;
      }
   }

   return mSignal;
}



