//#property strict	//+------------------------------------------------------------------+	
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
//| 11 グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
/*
int KAIRISPAN      = 70;							
int KAIRIBORDER    = 6;							
int KAIRIMA_Method = 2; //0から2まで							
int KAIRIApply     = 6;     //0から6まで							
int KAIRIMA_Period = 20;//移動平均iMAを計算する期間	
*/
//+------------------------------------------------------------------+
//|   entryTrendBB()                                               |
//+------------------------------------------------------------------+  
double     Kairi_buffer[1000];	

int entryKAIRI0() {
//KAIRISPAN  :最大でKAIRI_limit個のかい離計算結果のうち、オーダー判断に使うかい離個数。例：50
//KAIRIBORDER:売り境界線と買い境界線の計算に使うかい離個数。例：5
   int i;
   int ticket_num = 0;
   double KAIRI_max = 0.0;
   double KAIRI_min = 0.0;
   double sl = 0.0;
   double tp = 0.0;
   int mFlag = 0;
   
   if(KAIRIBORDER == 0) {
      return NO_SIGNAL;
   }
   if(KAIRISPAN < KAIRIBORDER) {
      return NO_SIGNAL;   
   }
   
   if(get_Trend_RSIandCCI(global_Period) == 0) return NO_SIGNAL; // 返り値０は、レンジ相場を意味する。
   int intBuf = ArrayInitialize(Kairi_buffer, 0);


   intBuf = calcMAConvDiv();
   
   double KAIRI_0  = Kairi_buffer[0];
   double KAIRI_1  = Kairi_buffer[1];
   
   // 計算したKairi_buffer[]のうち、直近のKAIRISPAN本目のシフトまでを計算に使う。
   // そのため、直近のKAIRISPAN本目のシフトまでを降順でソートする。
   ArraySort(Kairi_buffer,KAIRISPAN,0,MODE_DESCEND);

   // 直近のKAIRISPAN本目のシフトまでの先頭KAIRIBORDER個を使って、最大値の平均を求める。
   // KAIRISPAN本目の過去からさかのぼってKAIRIBORDER個を使って、最小値の平均を求める。
   for(i = 0; i < KAIRIBORDER; i++) {
   	KAIRI_max = KAIRI_max + Kairi_buffer[i];
   	KAIRI_min = KAIRI_min + Kairi_buffer[KAIRISPAN - 1 - i];
   }   

   KAIRI_max = NormalizeDouble(KAIRI_max / KAIRIBORDER, global_Digits); //最大かい離トップKAIRISPAN個の平均値＝売り境界線
   KAIRI_min = NormalizeDouble(KAIRI_min / KAIRIBORDER, global_Digits); //最小かい離トップKAIRISPAN個の平均値＝買い境界線

   // 売り境界線を上抜けたら売り（逆張り）
   // if(NormalizeDouble(Kairi_buffer[1], global_Digits) < NormalizeDouble(KAIRI_max, global_Digits) && NormalizeDouble(Kairi_buffer[0], global_Digits) >  NormalizeDouble(KAIRI_max, global_Digits)) {
   // 直近のかい離が、売り境界線を上抜けたら売り（逆張り）
   if(NormalizeDouble(KAIRI_1, global_Digits) < NormalizeDouble(KAIRI_max, global_Digits)
       && NormalizeDouble(KAIRI_0, global_Digits) >  NormalizeDouble(KAIRI_max, global_Digits)) {
      return SELL_SIGNAL;
   }
   // 買い境界線を下抜けたら買い
   // else if(NormalizeDouble(Kairi_buffer[1], global_Digits) > NormalizeDouble(KAIRI_min, global_Digits) && NormalizeDouble(Kairi_buffer[0], global_Digits) <  NormalizeDouble(KAIRI_min, global_Digits) ) {
   // 直近のかい離が、買い境界線を下抜けたら買い
   else if(NormalizeDouble(KAIRI_1, global_Digits) > NormalizeDouble(KAIRI_min, global_Digits) 
      && NormalizeDouble(KAIRI_0, global_Digits) <  NormalizeDouble(KAIRI_min, global_Digits) ) {
      return BUY_SIGNAL;
   }
   return NO_SIGNAL;
}



int calcMAConvDiv() {
//移動平均と現在値（Close, Open等）とのかい離率を計算し
//Kairi_buffer[]に計算結果を代入する。
   int KAIRI_limit = 200;
   double  KAIRIMA_buffer[200];
   ArrayInitialize(KAIRIMA_buffer, 0.0);
   int i;
   for(i=0; i<KAIRI_limit; i++) {
      switch(KAIRIMA_Method) {
         case 0 : 
            switch(KAIRIApply) {
               case 0 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMA,PRICE_CLOSE,i); break;
               case 1 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMA,PRICE_OPEN,i); break;
               case 2 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMA,PRICE_HIGH,i); break;
               case 3 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMA,PRICE_LOW,i); break;
               case 4 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMA,PRICE_MEDIAN,i); break;
               case 5 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMA,PRICE_TYPICAL,i); break;
               case 6 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMA,PRICE_WEIGHTED,i); break;
            }
            break;
         case 1 : 
            switch(KAIRIApply) {
               case 0 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_EMA,PRICE_CLOSE,i); break;
               case 1 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_EMA,PRICE_OPEN,i); break;
               case 2 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_EMA,PRICE_HIGH,i); break;
               case 3 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_EMA,PRICE_LOW,i); break;
               case 4 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_EMA,PRICE_MEDIAN,i); break;
               case 5 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_EMA,PRICE_TYPICAL,i); break;
               case 6 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_EMA,PRICE_WEIGHTED,i); break;
            }
            break;
         case 2 : 
            switch(KAIRIApply) {
               case 0 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMMA,PRICE_CLOSE,i); break;
               case 1 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMMA,PRICE_OPEN,i); break;
               case 2 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMMA,PRICE_HIGH,i); break;
               case 3 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMMA,PRICE_LOW,i); break;
               case 4 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMMA,PRICE_MEDIAN,i); break;
               case 5 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMMA,PRICE_TYPICAL,i); break;
               case 6 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_SMMA,PRICE_WEIGHTED,i); break;
            }
            break;
         case 3 : 
            switch(KAIRIApply) {
               case 0 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_LWMA,PRICE_CLOSE,i); break;
               case 1 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_LWMA,PRICE_OPEN,i); break;
               case 2 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_LWMA,PRICE_HIGH,i); break;
               case 3 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_LWMA,PRICE_LOW,i); break;
               case 4 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_LWMA,PRICE_MEDIAN,i); break;
               case 5 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_LWMA,PRICE_TYPICAL,i); break;
               case 6 : 
                  KAIRIMA_buffer[i]=iMA(global_Symbol,0,KAIRIMA_Period,0,MODE_LWMA,PRICE_WEIGHTED,i); break;
            }
            break;
      }
   }

   for(i=0; i<KAIRI_limit; i++) {
      if(KAIRIMA_buffer[i] == 0.0) continue;
         switch(KAIRIApply)
           {
            case 0 : 
               Kairi_buffer[i] = NormalizeDouble( (Close[i]-KAIRIMA_buffer[i])/KAIRIMA_buffer[i]*100, global_Digits*2); 
               break;
            case 1 : 
               Kairi_buffer[i] = NormalizeDouble((Open[i]-KAIRIMA_buffer[i])/KAIRIMA_buffer[i]*100, global_Digits*2); 
               break;
            case 2 : 
               Kairi_buffer[i] = NormalizeDouble((High[i]-KAIRIMA_buffer[i])/KAIRIMA_buffer[i]*100, global_Digits*2); 
               break;
            case 3 : 
               Kairi_buffer[i] = NormalizeDouble((Low[i]-KAIRIMA_buffer[i])/KAIRIMA_buffer[i]*100, global_Digits*2); 
               break;
            case 4 : 
               Kairi_buffer[i] = NormalizeDouble((((High[i]+Low[i])/2)-KAIRIMA_buffer[i])/KAIRIMA_buffer[i]*100-100, global_Digits*2); 
               break;
            case 5 : 
               Kairi_buffer[i] = NormalizeDouble((((High[i]+Low[i]+Close[i])/3)-KAIRIMA_buffer[i])/KAIRIMA_buffer[i]*100-100, global_Digits*2); 
               break;
            case 6 : 
               Kairi_buffer[i] = NormalizeDouble((((High[i]+Low[i]+Close[i]+Close[i])/4)-KAIRIMA_buffer[i])/KAIRIMA_buffer[i]*100-100, global_Digits*2); 
               break;
           }      
   }

   return(0);  


}

/*

void entryKAIRI() {
//KAIRISPAN  :最大でKAIRI_limit個のかい離計算結果のうち、オーダー判断に使うかい離個数。例：50
//KAIRIBORDER:売り境界線と買い境界線の計算に使うかい離個数。例：5
//かい離がプラスで大きいほど高値圏であり、マイナスに向かうほど安値圏であることを利用する。
   int i;
   int KAIRI_limit = 200;
   double  bufKAIRI_buffer[200];
   int ticket_num = 0;
   double KAIRI_max = 0.0;
   double KAIRI_min = 0.0;
   double sl = 0.0;
   double tp = 0.0;
   int mFlag = 0;
   double ATR_1 = 0.0;

   if(KAIRISPAN > KAIRI_limit) return ;   
   if(KAIRISPAN <= KAIRIBORDER) return ;

   //かい離率を計算してKairi_bufferに入れる。
   int intBuf = ArrayInitialize(Kairi_buffer, -9999);
   intBuf = calcMAConvDiv();


   //直近のKAIRISPAN個の値を降順で並べる。
   for(i = 0; i < KAIRI_limit;i++) {
      bufKAIRI_buffer[i] = Kairi_buffer[i];
   }
   ArraySort(bufKAIRI_buffer,KAIRISPAN,0,MODE_DESCEND);

   //有効なかい離の個数cntAvailableDataを数える。
   int cntAvailableData = 0;
   for(i = 0; i < KAIRI_limit;i++) {
	if(bufKAIRI_buffer[i] > -9999) {
		cntAvailableData = cntAvailableData + 1;
	}
   }

   //判断材料とするかい離の個数KAIRISPANが有効なかい離の個数cntAvailableDataを
   //超えている場合、判断材料とするかい離の個数KAIRISPANを減少させる。
   if(KAIRISPAN > cntAvailableData) {
	KAIRISPAN = cntAvailableData;
 	//境界線を計算するかい離個数が有効なかい離個数を超えている場合は何もしないで終了する。
        if(KAIRIBORDER < KAIRISPAN) {
		Print("境界線を計算するためのかい離個数が有効なかい離個数を超えました");
		return ;
	}
   }

   //境界線を計算する。
   for(i = 0; i < KAIRIBORDER; i++) {
   	KAIRI_max = KAIRI_max + bufKAIRI_buffer[i];
	KAIRI_min = KAIRI_min + bufKAIRI_buffer[KAIRISPAN - 1 - i];

   }   
   KAIRI_max = KAIRI_max / KAIRIBORDER; //最大かい離トップKAIRISPAN個の平均値＝売り境界線
   KAIRI_min = KAIRI_min / KAIRIBORDER; //最小かい離トップKAIRISPAN個の平均値＝買い境界線

   //かい離率が売り境界線を上抜けたら売り（逆張り）
   if(Kairi_buffer[1] < KAIRI_max && Kairi_buffer[0] >  KAIRI_max) {
      return SELL_SIGNAL;
   }
   //かい離率が買い境界線を下抜けたら買い（逆張り）
   else if(Kairi_buffer[1] > KAIRI_min && Kairi_buffer[0] <  KAIRI_min) {
      return BUY_SIGNAL;
   }
}

int entryKAIRI2() {  //KAIRI()に順張りを追加したバージョン
//KAIRISPAN  :最大でKAIRI_limit個のかい離計算結果のうち、オーダー判断に使うかい離個数。例：50
//KAIRIBORDER:売り境界線と買い境界線の計算に使うかい離個数。例：5
//かい離がプラスで大きいほど高値圏であり、マイナスに向かうほど安値圏であることを利用する。
   int i;
   int KAIRI_limit = 200;
   double  bufKAIRI_buffer[200];
   int ticket_num = 0;
   double KAIRI_max = 0.0;
   double KAIRI_min = 0.0;
   double sl = 0.0;
   double tp = 0.0;
   int mFlag = 0;
   double ATR_1 = 0.0;

   if(KAIRISPAN > KAIRI_limit) return NO_SIGNAL;   
   if(KAIRISPAN <= KAIRIBORDER) return NO_SIGNAL;

   //かい離率を計算してKairi_bufferに入れる。
   int intBuf = ArrayInitialize(Kairi_buffer, -9999);
   intBuf = calcMAConvDiv();


   //直近のKAIRISPAN個の値を降順で並べる。
   for(i = 0; i < KAIRI_limit;i++) {
      bufKAIRI_buffer[i] = Kairi_buffer[i];
   }
   ArraySort(bufKAIRI_buffer,KAIRISPAN,0,MODE_DESCEND);

   //有効なかい離の個数cntAvailableDataを数える。
   int cntAvailableData = 0;
   for(i = 0; i < KAIRI_limit;i++) {
	if(bufKAIRI_buffer[i] > -9999) {
		cntAvailableData = cntAvailableData + 1;
	}
   }

   //判断材料とするかい離の個数KAIRISPANが有効なかい離の個数cntAvailableDataを
   //超えている場合、判断材料とするかい離の個数KAIRISPANを減少させる。
   if(KAIRISPAN > cntAvailableData) {
	KAIRISPAN = cntAvailableData;
 	//境界線を計算するかい離個数が有効なかい離個数を超えている場合は何もしないで終了する。
        if(KAIRIBORDER < KAIRISPAN) {
		Print("境界線を計算するためのかい離個数が有効なかい離個数を超えました");
		return NO_SIGNAL;
	}
   }

   //境界線を計算する。
   for(i = 0; i < KAIRIBORDER; i++) {
   	KAIRI_max = KAIRI_max + bufKAIRI_buffer[i];
	KAIRI_min = KAIRI_min + bufKAIRI_buffer[KAIRISPAN - 1 - i];

   }   
   KAIRI_max = KAIRI_max / KAIRIBORDER; //最大かい離トップKAIRISPAN個の平均値＝売り境界線
   KAIRI_min = KAIRI_min / KAIRIBORDER; //最小かい離トップKAIRISPAN個の平均値＝買い境界線

   //かい離率が売り境界線を上抜けたら売り（逆張り）
   if(Kairi_buffer[1] < KAIRI_max && Kairi_buffer[0] >  KAIRI_max) {
      return SELL_SIGNAL;
   }
   //かい離率が売り境界線を下抜け、長期足が下落傾向ならば売り（順張り）
   else if(Kairi_buffer[1] > KAIRI_max && Kairi_buffer[0] <  KAIRI_max && isLongSpanTrend(240) < 0) {
      return SELL_SIGNAL;
   }
   //かい離率が買い境界線を下抜けたら買い（逆張り）
   else if(Kairi_buffer[1] > KAIRI_min && Kairi_buffer[0] <  KAIRI_min) {
      return BUY_SIGNAL;
   }
   //かい離率が買い境界線を上抜け、長期足が上昇傾向ならば買い（順張り）
   else if(Kairi_buffer[1] < KAIRI_min && Kairi_buffer[0] >  KAIRI_min && isLongSpanTrend(240) > 0) {
	   return BUY_SIGNAL;
   }
   return NO_SIGNAL;
}

*/

