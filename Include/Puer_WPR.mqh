//#property strict	
//+------------------------------------------------------------------+	
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
double WPRLow  = -95; //ウィリアムズWPRのLow						
double WPRHigh = -65; //ウィリアムズWPRのHigh	「-20%を超えれば買われ過ぎで「売りサイン」
int WPRgarbage = 50;  //過去WPRgarbage個のWPRのうち、WPRgarbageRate％の割合で
		                //WPRLowを下回っている個数があれば売りとみなす（ガーベージボトム）
double WPRgarbageRate = 65.0;
*/


//+------------------------------------------------------------------+
//|08.WPR                                                 　　　　　      |
//+------------------------------------------------------------------+
int entryRangeWPR() {
/*
ガーベージトップとは％Ｒの値が0％付近を何度かタッチしてから－20％の 
ハイ･ラインを下抜けたときが上昇から下降への売りシグナルと判断することができます。 
逆にガーベージボトムという形も見られます。 ％Ｒが何度か－100％をタッチしてから、
－80％のローラインを上抜けたときが買いシグナルです。
*/
//   if(WPRHigh <= WPRLow) return NO_SIGNAL;
   if(WPRHigh >=0) return NO_SIGNAL;
   if(WPRLow  >= 0) return NO_SIGNAL;
 //20221214廃止   if(get_Trend_RSIandCCI(global_Period) != NoTrend) return NO_SIGNAL;  //レンジ以外の場合はfalseを返して終了する。   	

   int i;
   int garbageCnt = 0;
	   	
   double mWPR1 = iWPR(global_Symbol,0,14,1);
   double mWPR2 = iWPR(global_Symbol,0,14,2);

   double ShortMA = iMA(global_Symbol,0,5 ,0,MODE_EMA,PRICE_CLOSE,1);
   double MidMA   = iMA(global_Symbol,0,13,0,MODE_EMA,PRICE_CLOSE,1);   
   double LongMA  = iMA(global_Symbol,0,25,0,MODE_EMA,PRICE_CLOSE,1);
/*printf( "[%d]テスト mWPR1=%s > WPRHigh=%s" , __LINE__, DoubleToStr(mWPR1, global_Digits), DoubleToStr(WPRHigh, global_Digits));
printf( "[%d]テスト mWPR2=%s < WPRHigh=%s" , __LINE__, DoubleToStr(mWPR2, global_Digits), DoubleToStr(WPRHigh, global_Digits));
printf( "[%d]テスト Close[1]=%s < ShortMA=%s" , __LINE__, DoubleToStr(Close[1], global_Digits), DoubleToStr(ShortMA, global_Digits));*/

   //ウィリアムズ％R
   //
   //売りサイン
   //「-20%を超えれば買われ過ぎで「売りサイン」
   //移動平均が上から長期、中期、短期（＝売りサイン）
   //Close[1]が短期より下
   int mSignal = NO_SIGNAL;
   if(NormalizeDouble(ShortMA, global_Digits) < NormalizeDouble(MidMA, global_Digits) 
      && NormalizeDouble(MidMA, global_Digits) < NormalizeDouble(LongMA, global_Digits) 
      && NormalizeDouble(mWPR1, global_Digits) > NormalizeDouble(WPRHigh, global_Digits)
      && NormalizeDouble(mWPR2, global_Digits) < NormalizeDouble(WPRHigh, global_Digits)   ) {
//printf( "[%d]WPR SELL候補１" , __LINE__);
      
      if(NormalizeDouble(Close[1], global_Digits) < NormalizeDouble(ShortMA, global_Digits)) {
         //過去WPRgarbage個のWPRのうち、WPRgarbageRate％の割合で
         //WPRHighを超えている個数があれば売りとみなす（ガーベージトップ）
         garbageCnt = 0;
//printf( "[%d]WPR SELL候補２" , __LINE__);         
         for(i = 3; i < WPRgarbage + 3; i++) {
            if(NormalizeDouble(iWPR(global_Symbol,0,14,i), global_Digits) > NormalizeDouble(WPRHigh, global_Digits)) {
               garbageCnt = garbageCnt + 1;
            }
         }
/*printf( "[%d]WPR SELL候補3garbageCnt=%s　レート=%s" , __LINE__, DoubleToStr(NormalizeDouble(garbageCnt, global_Digits), global_Digits), 
DoubleToStr(NormalizeDouble(WPRgarbage, global_Digits) * NormalizeDouble((WPRgarbageRate / 100), global_Digits), global_Digits)
);*/         

         if(garbageCnt >= NormalizeDouble(WPRgarbage, global_Digits) * NormalizeDouble((WPRgarbageRate / 100), global_Digits)) {
            mSignal = SELL_SIGNAL;
         }
      }
   }

   //買いサイン
   //「-80％を下回れば売られ過ぎで買いサイン」
   //移動平均が上から短期、中期、長期（＝買いサイン）
   //Close[1]が長期より上
   //長期足（60分足）で上昇中

   if(NormalizeDouble(ShortMA, global_Digits) > NormalizeDouble(MidMA, global_Digits) 
      && NormalizeDouble(MidMA, global_Digits) > NormalizeDouble(LongMA, global_Digits) 
      && NormalizeDouble(mWPR1, global_Digits) < NormalizeDouble(WPRLow, global_Digits) 
      && NormalizeDouble(mWPR2, global_Digits > NormalizeDouble(WPRLow, global_Digits) )) {
//printf( "[%d]WPR BUY候補１" , __LINE__);      
      if(NormalizeDouble(Close[1], global_Digits) > NormalizeDouble(LongMA, global_Digits) ) {
         //過去WPRgarbage個のWPRのうち、WPRgarbageRate％の割合で
         //WPRLowを下回っている個数があれば売りとみなす（ガーベージボトム）
//printf( "[%d]WPR BUY候補２" , __LINE__);         
         garbageCnt = 0;
         for(i = 3; i < WPRgarbage + 3; i++) {
            if(NormalizeDouble(iWPR(global_Symbol,0,14,i), global_Digits) < NormalizeDouble(WPRLow, global_Digits)) {
               garbageCnt = garbageCnt + 1;
            }
         }
/*printf( "[%d]WPR BUY候補3garbageCnt=%s　レート=%s" , __LINE__, DoubleToStr(NormalizeDouble(garbageCnt, global_Digits), global_Digits), 
DoubleToStr(NormalizeDouble(WPRgarbage, global_Digits) * NormalizeDouble((WPRgarbageRate / 100), global_Digits), global_Digits)
);*/         
         
         if(NormalizeDouble(garbageCnt, global_Digits) >= NormalizeDouble(WPRgarbage, global_Digits) * NormalizeDouble((WPRgarbageRate / 100), global_Digits)) {
            mSignal = BUY_SIGNAL;
         }
      }
   }

   return mSignal;
}	


int entryRangeWPR(int mShift) {
/*
ガーベージトップとは％Ｒの値が0％付近を何度かタッチしてから－20％の 
ハイ･ラインを下抜けたときが上昇から下降への売りシグナルと判断することができます。 
逆にガーベージボトムという形も見られます。 ％Ｒが何度か－100％をタッチしてから、
－80％のローラインを上抜けたときが買いシグナルです。
*/
//   if(WPRHigh <= WPRLow) return NO_SIGNAL;
   if(WPRHigh >=0) return NO_SIGNAL;
   if(WPRLow  >= 0) return NO_SIGNAL;
  //20221214廃止 if(get_Trend_RSIandCCI(global_Period) != NoTrend) return NO_SIGNAL;  //レンジ以外の場合はfalseを返して終了する。   	

   int i;
   int garbageCnt = 0;
	   	
   double mWPR1 = NormalizeDouble(iWPR(global_Symbol,0,14,mShift + 1), global_Digits);
   double mWPR2 = NormalizeDouble(iWPR(global_Symbol,0,14,mShift + 2), global_Digits);

   double ShortMA = NormalizeDouble(iMA(global_Symbol,0,5 ,0,MODE_EMA,PRICE_CLOSE,mShift + 1), global_Digits);
   double MidMA   = NormalizeDouble(iMA(global_Symbol,0,13,0,MODE_EMA,PRICE_CLOSE,mShift + 1), global_Digits);
   double LongMA  = NormalizeDouble(iMA(global_Symbol,0,25,0,MODE_EMA,PRICE_CLOSE,mShift + 1), global_Digits);
/*printf( "[%d]テスト mWPR1=%s > WPRHigh=%s" , __LINE__, DoubleToStr(mWPR1, global_Digits), DoubleToStr(WPRHigh, global_Digits));
printf( "[%d]テスト mWPR2=%s < WPRHigh=%s" , __LINE__, DoubleToStr(mWPR2, global_Digits), DoubleToStr(WPRHigh, global_Digits));
printf( "[%d]テスト Close[1]=%s < ShortMA=%s" , __LINE__, DoubleToStr(Close[1], global_Digits), DoubleToStr(ShortMA, global_Digits));*/

   //ウィリアムズ％R
   //
   //売りサイン
   //「-20%を超えれば買われ過ぎで「売りサイン」
   //移動平均が上から長期、中期、短期（＝売りサイン）
   //Close[1]が短期より下
   int mSignal = NO_SIGNAL;
   if(NormalizeDouble(ShortMA, global_Digits) < NormalizeDouble(MidMA, global_Digits) 
      && NormalizeDouble(MidMA, global_Digits) < NormalizeDouble(LongMA, global_Digits) 
      && NormalizeDouble(mWPR1, global_Digits) > NormalizeDouble(WPRHigh, global_Digits)
      && NormalizeDouble(mWPR2, global_Digits) < NormalizeDouble(WPRHigh, global_Digits)   ) {
//printf( "[%d]WPR SELL候補１" , __LINE__);
      
      if(NormalizeDouble(Close[mShift + 1], global_Digits) < NormalizeDouble(ShortMA, global_Digits)) {
         //過去WPRgarbage個のWPRのうち、WPRgarbageRate％の割合で
         //WPRHighを超えている個数があれば売りとみなす（ガーベージトップ）
         garbageCnt = 0;
//printf( "[%d]WPR SELL候補２" , __LINE__);         
         for(i = 3; i < WPRgarbage + 3; i++) {
            if(NormalizeDouble(iWPR(global_Symbol,0,14,mShift + i), global_Digits) > NormalizeDouble(WPRHigh, global_Digits)) {
               garbageCnt = garbageCnt + 1;
            }
         }
/*printf( "[%d]WPR SELL候補3garbageCnt=%s　レート=%s" , __LINE__, DoubleToStr(NormalizeDouble(garbageCnt, global_Digits), global_Digits), 
DoubleToStr(NormalizeDouble(WPRgarbage, global_Digits) * NormalizeDouble((WPRgarbageRate / 100), global_Digits), global_Digits)
);*/         

         if(garbageCnt >= NormalizeDouble(WPRgarbage, global_Digits) * NormalizeDouble((WPRgarbageRate / 100), global_Digits)) {
            mSignal = SELL_SIGNAL;
         }
      }
   }

   //買いサイン
   //「-80％を下回れば売られ過ぎで買いサイン」
   //移動平均が上から短期、中期、長期（＝買いサイン）
   //Close[1]が長期より上
   //長期足（60分足）で上昇中

   if(NormalizeDouble(ShortMA, global_Digits) > NormalizeDouble(MidMA, global_Digits) 
      && NormalizeDouble(MidMA, global_Digits) > NormalizeDouble(LongMA, global_Digits) 
      && NormalizeDouble(mWPR1, global_Digits) < NormalizeDouble(WPRLow, global_Digits) 
      && NormalizeDouble(mWPR2, global_Digits > NormalizeDouble(WPRLow, global_Digits) )) {
//printf( "[%d]WPR BUY候補１" , __LINE__);      
      if(NormalizeDouble(Close[mShift + 1], global_Digits) > NormalizeDouble(LongMA, global_Digits) ) {
         //過去WPRgarbage個のWPRのうち、WPRgarbageRate％の割合で
         //WPRLowを下回っている個数があれば売りとみなす（ガーベージボトム）
//printf( "[%d]WPR BUY候補２" , __LINE__);         
         garbageCnt = 0;
         for(i = 3; i < WPRgarbage + 3; i++) {
            if(NormalizeDouble(iWPR(global_Symbol,0,14,mShift + i), global_Digits) < NormalizeDouble(WPRLow, global_Digits)) {
               garbageCnt = garbageCnt + 1;
            }
         }
/*printf( "[%d]WPR BUY候補3garbageCnt=%s　レート=%s" , __LINE__, DoubleToStr(NormalizeDouble(garbageCnt, global_Digits), global_Digits), 
DoubleToStr(NormalizeDouble(WPRgarbage, global_Digits) * NormalizeDouble((WPRgarbageRate / 100), global_Digits), global_Digits)
);*/         
         
         if(NormalizeDouble(garbageCnt, global_Digits) >= NormalizeDouble(WPRgarbage, global_Digits) * NormalizeDouble((WPRgarbageRate / 100), global_Digits)) {
            mSignal = BUY_SIGNAL;
         }
      }
   }

   return mSignal;
}	


