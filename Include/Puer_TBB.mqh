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
int TBBSigma    = 2;  // 何σの値を超えた時に売買シグナルを設定するか。
int TBTimeframe = 0;  // 計算対象とする時間軸
*/
//+------------------------------------------------------------------+
//|   No.20 entryTrendBB()                                               |
//+------------------------------------------------------------------+  
int entryTrendBB() {
   //トレンドがなくて、終値が2σを超えたら逆張り。 
   //トレンドがあって、終値が2σを超えたら順張り。

   // 1つ上の時間軸でトレンドが発生していなければ、NO_SIGNALを返す。
   // １つ上の時間軸を入手する。
   // ただし、現在の時間足が最大のPERIOD_MN1の場合は、1つ上はないため、そのまま。
   int tfNow = 0;
   int tf1UP = 0; 
   tfNow = TBTimeframe;
   // 引数mCurrTFで渡した時間軸（0～9。ENUM_TIMEFRAMES型ではない)に対して、
   // 引数mUpperLowerで渡しただけ上か下の時間軸（0～9。ENUM_TIMEFRAMES型ではない)を返す
   // 【注意】
   // ・引数も返り値も0(PERIOD_00_INT)～9(PERIOD_MN1_INT)であり、ENUM_TIMEFRAMES型ではない。
   tf1UP = get_UpperLowerPeriodFrom1To9(tfNow,  //　現在の時間軸。0,1(PERIOD_M1)～9(PERIOD_MN1)
                                        1       // いくつ上下の時間軸を返すか。1つ上ならば+1、1つ下ならば-1
                                       );

//printf( "[%d]TBB　0--9から変換前。念のため、確認tfNow=%d より1つ上の時間軸が、tf1UP=%d", __LINE__, tfNow, tf1UP);                                 
   tfNow = getTimeFrame(tfNow);                                       
   tf1UP = getTimeFrame(tf1UP);                                       

//printf( "[%d]TBB　念のため、確認tfNow=%d より1つ上の時間軸が、tf1UP=%d", __LINE__, tfNow, tf1UP);                                 
 
   int tf1UPTrend = get_Trend_EMA(tf1UP);
   if(tf1UPTrend == NoTrend) {
      return NO_SIGNAL;
   }

   int BUYSELLsignal = NO_SIGNAL;
   int flgTrend = get_Trend_RSIandCCI(tfNow);

   double bandMODE_LOWER    = iBands( global_Symbol, tfNow, 200, TBBSigma,   0, PRICE_CLOSE, MODE_LOWER, 1);
   double bandMODE_UPPER    = iBands( global_Symbol, tfNow, 200, TBBSigma,   0, PRICE_CLOSE, MODE_UPPER, 1);
   double m_iHigh = iHigh(global_Symbol, tfNow, 1);
   double m_iLow  = iLow(global_Symbol, tfNow, 1);
   
   if(flgTrend == NoTrend) {          //トレンドが無い場合
      if(NormalizeDouble(m_iHigh, global_Digits) < NormalizeDouble(bandMODE_LOWER, global_Digits) ) {   //終値がBBの下限を下回った場合
         BUYSELLsignal = BUY_SIGNAL;    //逆張りのロング
      }
      else if(NormalizeDouble(m_iLow, global_Digits) > NormalizeDouble(bandMODE_UPPER, global_Digits) ) {   //終値がBBの上限を上回った場合
         BUYSELLsignal = SELL_SIGNAL;        //逆張りのショート
      }
   }
   
   else if(flgTrend == UpTrend){      //上昇トレンドの場合
      if(NormalizeDouble(m_iLow, global_Digits) > NormalizeDouble(bandMODE_UPPER, global_Digits) ) {   //終値がBBの上限を上回った場合
         BUYSELLsignal = BUY_SIGNAL;    //順張りのロング
      }
   }
   else if(flgTrend == DownTrend){     //下昇トレンドの場合
      if(NormalizeDouble(m_iHigh, global_Digits) < NormalizeDouble(bandMODE_LOWER, global_Digits) ) {   //終値がBBの下限を下回った場合
         BUYSELLsignal = SELL_SIGNAL;   //順張りのショート
      }
   }



   return BUYSELLsignal;
}






