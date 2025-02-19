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
int BBandSIGMA = 2  ;        //ボリンジャーバンドで逆張りを入れるσ値。4σで逆張りするなら4。
*/
 
//+------------------------------------------------------------------+
//|04.ボリンジャーBB                                                 |
//+------------------------------------------------------------------+
int entryWithBB() {
   int entry_sig = judgeBuySell_BB(BBandSIGMA);
   if(entry_sig != BUY_SIGNAL && entry_sig != SELL_SIGNAL) return NO_SIGNAL;

	
   //注文送信処理(ロング)	
   if(entry_sig == BUY_SIGNAL) {         	
      return BUY_SIGNAL;
   }	
   //注文送信処理(ショート)---Start	
   else if(entry_sig == SELL_SIGNAL){	
      return SELL_SIGNAL; 
   }	
     //注文送信処理(ショート)---End	
   return entry_sig;
}


//+------------------------------------------------------------------+
//|ボリバンを使った売買判断                     　　　　　      |
//+------------------------------------------------------------------+ 	
int judgeBuySell_BB(double BBandS){
//1.ローソク足の実体が±2σを抜けたらトレンド発生
//省略2.ローソク足のヒゲが±2σを抜けただけの時はダマシの可能性あり
//3.ローソク足が±3σにタッチしたらトレンド発生
//省略4.レンジ相場では±2σ抜けや±3σタッチで逆張り

   double bandMODE_LOWER    = iBands( global_Symbol, 0, 20, BBandS,   0, PRICE_CLOSE, MODE_LOWER, 2);
   double bandMODE_UPPER    = iBands( global_Symbol, 0, 20, BBandS,   0, PRICE_CLOSE, MODE_UPPER, 2);
   double bandMODE_LOWER_1  = iBands( global_Symbol, 0, 20, BBandS+1, 0, PRICE_CLOSE, MODE_LOWER, 1);	
   double bandMODE_UPPER_1  = iBands( global_Symbol, 0, 20, BBandS+1, 0, PRICE_CLOSE, MODE_UPPER, 1);
   
   double open_2  = Open[2];
   double close_1 = Close[1];
   double close_2 = Close[2];

   //ローソク足の実体Open[2]>Close[2]が+BBandS_σ(例えば、+2σ）を抜けたら上昇トレンド発生
   //ローソク足Close[1]が、(BBandS+1)σ(例えば、+3σ）にタッチしたら上昇トレンド発生
   if(NormalizeDouble(open_2, global_Digits) > NormalizeDouble(bandMODE_UPPER, global_Digits) 
      && NormalizeDouble(close_2, global_Digits) > NormalizeDouble(open_2, global_Digits) 
      && NormalizeDouble(close_1, global_Digits) > NormalizeDouble(bandMODE_UPPER_1, global_Digits)) {
      return BUY_SIGNAL;
   }

   //ローソク足の実体Close[2]<Open[2]が-BBandS_σ(例えば、-2σ）を抜けたら下降トレンド発生
   //ローソク足Close[1]が-(BBandS+1)σ(例えば、-3σ）にタッチしたら下降トレンド発生
   if(NormalizeDouble(open_2, global_Digits) < NormalizeDouble(bandMODE_LOWER, global_Digits) 
      && NormalizeDouble(close_2, global_Digits) < NormalizeDouble(open_2, global_Digits) 
      && NormalizeDouble(close_1, global_Digits) < NormalizeDouble(bandMODE_LOWER_1, global_Digits)) {  
      return SELL_SIGNAL;
   }

   return NO_SIGNAL;
}
