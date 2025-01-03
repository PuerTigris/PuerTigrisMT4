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
double SAR_ADX = 15.0;  //パラボリックSARにおいてこの値より上で取引を行う。
*/
//+------------------------------------------------------------------+
//|   12 entryTrendBB()                                               |
//+------------------------------------------------------------------+  
/*
2～4本前のバーのパラボリックSARの値が2～4本前のバーの高値よりも大きく、
かつ1本前のバーのパラボリックSARの値が1本前のバーの安値よりも小さければ、
買いエントリーかつDMI(+)がDMI(－)を上抜けしたところが買いエントリー
2～4本前のバーのパラボリックSARの値が2～4本前のバーの安値よりも小さく、
かつ1本前のバーのパラボリックSARの値が1本前のバーの高値よりも大きければ、
売りエントリーかつDMI(+)がDMI(－)を下抜けしたところが売りエントリー

※ボックス相場のようにトレンドがない相場の場合は、頻繁にシグナルがでてしまいダマシが多くなる傾向
*/

int entrySAR() {
   // ※ボックス相場のようにトレンドがない相場の場合は、頻繁にシグナルがでてしまいダマシが多くなる傾向
   if(get_Trend_RSIandCCI(global_Period) == NoTrend) {
      return NO_SIGNAL;
   }

   // ADXを用いた売買判定
   // DMI(+)がDMI(－)を上抜けしたところが買いエントリー
   // DMI(+)がDMI(－)を下抜けしたところが売りエントリー
   int buysellSignal = isEntrywithDIADX(SAR_ADX);	
   if(buysellSignal != BUY_SIGNAL && buysellSignal != SELL_SIGNAL) {
   	return NO_SIGNAL;
   }

   double SAR_1 = iSAR(global_Symbol, global_Period, 0.2, 0.02, 1);
   double SAR_2 = iSAR(global_Symbol, global_Period, 0.2, 0.02, 2);
   double SAR_3 = iSAR(global_Symbol, global_Period, 0.2, 0.02, 3);
   double SAR_4 = iSAR(global_Symbol, global_Period, 0.2, 0.02, 4);
  
/*printf( "[%d]SAR SAR_1=%s  SAR_2=%s  SAR_3=%s  SAR_4=%s" , __LINE__,
         DoubleToStr(SAR_1, global_Digits),
         DoubleToStr(SAR_2, global_Digits),
         DoubleToStr(SAR_3, global_Digits),
         DoubleToStr(SAR_4, global_Digits)                       
); 
*/  
/*
   2～4本前のバーのパラボリックSARの値が2～4本前のバーの高値よりも大きく、
   かつ1本前のバーのパラボリックSARの値が1本前のバーの安値よりも小さければ、買いエントリー
*/
   if(buysellSignal == BUY_SIGNAL) {
      if(NormalizeDouble(SAR_4, global_Digits) > NormalizeDouble(High[4], global_Digits) 
         && NormalizeDouble(SAR_3, global_Digits) > NormalizeDouble(High[3], global_Digits) 
         && NormalizeDouble(SAR_2, global_Digits) > NormalizeDouble(High[2], global_Digits) 
         && NormalizeDouble(SAR_1, global_Digits) < NormalizeDouble(Low[1], global_Digits)
         ) {
         return BUY_SIGNAL;
      }
   }
   /*
   else if(buysellSignal == BUY_SIGNAL) {
printf( "[%d]SAR SAR_1=%s  <  LOW[1]=%s" , __LINE__,
         DoubleToStr(SAR_1, global_Digits),
         DoubleToStr(Low[1], global_Digits)                      
);    
printf( "[%d]SAR SAR_2=%s  >  HIGH[2]=%s" , __LINE__,
         DoubleToStr(SAR_2, global_Digits),
         DoubleToStr(High[2], global_Digits)                      
);    
printf( "[%d]SAR SAR_3=%s  >  HIGH[3]=%s" , __LINE__,
         DoubleToStr(SAR_3, global_Digits),
         DoubleToStr(High[3], global_Digits)                      
);    
printf( "[%d]SAR SAR_4=%s  >  HIGH[4]=%s" , __LINE__,
         DoubleToStr(SAR_4, global_Digits),
         DoubleToStr(High[4], global_Digits)                      
);    
   }*/


/*
   2～4本前のバーのパラボリックSARの値が2～4本前のバーの安値よりも小さく、
   かつ1本前のバーのパラボリックSARの値が1本前のバーの高値よりも大きければ、売りエントリー
*/
   else if(buysellSignal == SELL_SIGNAL) {
      if(NormalizeDouble(SAR_4, global_Digits) < NormalizeDouble(Low[4], global_Digits) 
           && NormalizeDouble(SAR_3, global_Digits) < NormalizeDouble(Low[3], global_Digits) 
           && NormalizeDouble(SAR_2, global_Digits) < NormalizeDouble(Low[2], global_Digits) 
           && NormalizeDouble(SAR_1, global_Digits) > NormalizeDouble(High[1], global_Digits) 
           ) {
           return SELL_SIGNAL;
      }
   }
   /*
   else if(buysellSignal == SELL_SIGNAL) {
printf( "[%d]SAR SAR_1=%s  <  LOW[1]=%s" , __LINE__,
         DoubleToStr(SAR_1, global_Digits),
         DoubleToStr(Low[1], global_Digits)                      
);    
printf( "[%d]SAR SAR_2=%s  >  HIGH[2]=%s" , __LINE__,
         DoubleToStr(SAR_2, global_Digits),
         DoubleToStr(High[2], global_Digits)                      
);    
printf( "[%d]SAR SAR_3=%s  >  HIGH[3]=%s" , __LINE__,
         DoubleToStr(SAR_3, global_Digits),
         DoubleToStr(High[3], global_Digits)                      
);    
printf( "[%d]SAR SAR_4=%s  >  HIGH[4]=%s" , __LINE__,
         DoubleToStr(SAR_4, global_Digits),
         DoubleToStr(High[4], global_Digits)                      
);    
   }   */
   return NO_SIGNAL;
}


//+------------------------------------------------------------------+
//| ADXを使った売買判定   　                         　　      |
//+------------------------------------------------------------------+
int isEntrywithDIADX(double mADX) {  
	double Plus_DI_1  = iADX(global_Symbol,global_Period,14,0,1,1);
	double Plus_DI_2  = iADX(global_Symbol,global_Period,14,0,1,2);
	double Minus_DI_1 = iADX(global_Symbol,global_Period,14,0,2,1);
	double Minus_DI_2 = iADX(global_Symbol,global_Period,14,0,2,2);
	double ADX_1      = iADX(global_Symbol,global_Period,14,0,0,1);

/*printf( "[%d]SAR Plus_DI_1=%s  Plus_DI_2=%s  Minus_DI_1=%s  Minus_DI_2=%s  ADX=%s　mADX=%s" , __LINE__ ,
    DoubleToStr(Plus_DI_1, global_Digits),
    DoubleToStr(Plus_DI_2, global_Digits),
    DoubleToStr(Minus_DI_1, global_Digits),
    DoubleToStr(Minus_DI_2, global_Digits),
    DoubleToStr(ADX_1, global_Digits),
    DoubleToStr(mADX, global_Digits) );*/
    
	//買いシグナル条件＝DI+がDI-を上抜き、ADXがmADX以上であれば買い
	if(NormalizeDouble(Plus_DI_2, global_Digits) <= NormalizeDouble(Minus_DI_2, global_Digits) 
          && NormalizeDouble(Plus_DI_1, global_Digits) >= NormalizeDouble(Minus_DI_1, global_Digits) 
          && NormalizeDouble(ADX_1, global_Digits) >= NormalizeDouble(mADX, global_Digits)) {
//printf( "[%d]SAR 買いシグナル" , __LINE__);
          
		return BUY_SIGNAL;
	}

	//売りシグナル条件＝DI+がDI-を下抜き、ADXがmADX以上であれば売り
	if(NormalizeDouble(Plus_DI_2, global_Digits) >= NormalizeDouble(Minus_DI_2, global_Digits) 
          && NormalizeDouble(Plus_DI_1, global_Digits) <= NormalizeDouble(Minus_DI_1, global_Digits) 
          && NormalizeDouble(ADX_1, global_Digits) >= NormalizeDouble(mADX, global_Digits)) {
//printf( "[%d]SAR 売りシグナル" , __LINE__);
		return SELL_SIGNAL;
	}

	return NO_SIGNAL;
}