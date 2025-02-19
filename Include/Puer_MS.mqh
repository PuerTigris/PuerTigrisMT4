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
int    MSTFIndex    = 1;    // 0から9。2は、PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
double MSMoveSpeed  = 5.0;  // 単位時間当たり、何pips移動するか。15分足で計算した時、大きくても10前後。
int    MSJUDGELEVEL = 1;    // 1～3。1:スピードの正負のみ。2:MAとMACDどちらかのGCやDCが条件を満たす。3:MAとMACD両方のGCやDCが条件を満たす。
*/
//+------------------------------------------------------------------+
//|  No.19 entryMoveSpeed()                                               |
//+------------------------------------------------------------------+  

int entryMoveSpeed() {
   // 時間軸をENUM_TIMEFRAMES(PERIOD_M1 = 1, PERIOD_M5 = 5など）＝分単位に変換する。
   int MSTime = getTimeFrame(MSTFIndex);
   
   //MACDを取得する。
   double MACD_1   = iMACD(global_Symbol,0,12,26,9,0,0,1);   
   double MACD_2   = iMACD(global_Symbol,0,12,26,9,0,0,2);   
   double Signal_1 = iMACD(global_Symbol,0,12,26,9,0,1,1);   
   double Signal_2 = iMACD(global_Symbol,0,12,26,9,0,1,2);
   
/*
20220427　取得した値が負の場合は無意味とした処理は誤り。
https://binaryoption-saizyo.xyz/binary-macd-indicator/
MACD線は「短期の指数平滑移動平均（EMA）－長期の指数平滑移動平均（EMA）」で算出されるラインで、両者の乖離の大きさがそのまま反映されています。

   double MACD_1   = iMACD(global_Symbol,0,12,26,9,0,0,1);
   if(MACD_1 <= 0.0) {
      printf("[%d]MSエラー >%s< >%s<  MACD_1の取得を失敗。%s" , __LINE__, global_Symbol, TimeToStr(Time[0]), DoubleToStr(MACD_1));
      return NO_SIGNAL;
   }
   else {
      printf("[%d]MS    >%s< >%s<  MACD_1の取得成功。%s" , __LINE__, global_Symbol, TimeToStr(Time[0]), DoubleToStr(MACD_1));   
   } 
   double MACD_2   = iMACD(global_Symbol,0,12,26,9,0,0,2);

   if(MACD_2 <= 0.0) {
      printf("[%d]MSエラー MACD_2の取得を失敗。%s" , __LINE__, DoubleToStr(MACD_2));
      return NO_SIGNAL;
   }   
   double Signal_1 = iMACD(global_Symbol,0,12,26,9,0,1,1);
   if(Signal_1 <= 0.0) {
      printf("[%d]MSエラー Signal_1の取得を失敗。%s" , __LINE__, DoubleToStr(Signal_1));
      return NO_SIGNAL;
   }   
   double Signal_2 = iMACD(global_Symbol,0,12,26,9,0,1,2);
   if(Signal_2 <= 0.0) {
      printf("[%d]MSエラー Signal_の取得を失敗。%s" , __LINE__, DoubleToStr(Signal_2));
      return NO_SIGNAL;
   }   
*/


   double MS_Pips = 0.0;

   //
   //移動速度を計算する。
   //

   
   if(MSTime == 0) {
      MSTime = Time[0] - Time[1]; // 時間軸の1シフト当たりが何分かを取得する。Period()と同じ。      
      if(MSTime <= 0) { //Period()を使ってもtimegrameを取得できない場合は、中止。
         printf("[%d]MSエラー 時間軸の取得を失敗。" , __LINE__);
         return NO_SIGNAL;
      }
   }

   double MSPoint = NormalizeDouble(Close[1], global_Digits) - NormalizeDouble(Close[2], global_Digits); // １つ前と２つ前の差分を距離とみなす。Close値が下降中なら、マイナス。
   // 変動をPIPS単位に変換する。
   if(global_Points != 0) {
      MS_Pips = NormalizeDouble(MSPoint / global_Points, global_Digits);    
   }
   else {
      return NO_SIGNAL;
   }
   
   double MSSpeed = 0.0;
   // 速度（＝1分当たりの変動PIPS数）を計算する。
   if(MSTime != 0) {
      MSSpeed = NormalizeDouble(MS_Pips / (double)MSTime, global_Digits);
   }
   else {
      return NO_SIGNAL;
   }

   // 1:スピードの正負のみ。2:MAとMACDどちらかのGCやDCが条件を満たす。3:MAとMACD両方のGCやDCが条件を満たす。
   if(MSJUDGELEVEL == 1) {
      if(MSSpeed > 0.0) {
         return BUY_SIGNAL;
      }
      else if(MSSpeed < 0.0) {
         return SELL_SIGNAL;
      }
      else {
         return NO_SIGNAL;
      }
   }

   // 1:スピードの正負のみ。2:MAとMACDどちらかのGCやDCが条件を満たす。3:MAとMACD両方のGCやDCが条件を満たす。
   else if(MSJUDGELEVEL >= 2) {
      // MAのGCとDCを取得する。
      int lastGC_MA = INT_VALUE_MIN;
      int lastDC_MA = INT_VALUE_MIN;
      bool flag_getLastMA_Cross = getLastMA_Cross(global_Period, 1, lastGC_MA, lastDC_MA);

      // MACDのGCとDCを取得する。
      int lastGC_MACD = INT_VALUE_MIN;
      int lastDC_MACD = INT_VALUE_MIN;
      bool flag_getLastMACD_Cross = getLastMACD_Cross(global_Period, 1, lastGC_MACD, lastDC_MACD);

      // MAとMACD両方で失敗した場合は、NO_SIGNAL
      if(flag_getLastMA_Cross == false && flag_getLastMACD_Cross == false) {
         return NO_SIGNAL;
      }
      if(lastGC_MA < 0 && lastDC_MA < 0) {
         return NO_SIGNAL;
      }
      if(lastGC_MACD < 0 && lastDC_MACD < 0) {
         return NO_SIGNAL;
      }
      
      // 1:スピードの正負のみ。2:MAとMACDどちらかのGCやDCが条件を満たす。3:MAとMACD両方のGCやDCが条件を満たす。
      if(MSJUDGELEVEL == 2) {
         //ゴールデンクロスの時、移動速度が+moveSpeed(points/minutes)より大きければ、買い。→ゴールデンクロスが発生した直後を条件とすると厳しいので、GCがDCより近いことで良しとする。
         if( ( (lastGC_MA < lastDC_MA && lastGC_MA >= 0) || (lastGC_MACD < lastDC_MACD && lastGC_MACD >= 0))
               &&
             (NormalizeDouble(MSSpeed, global_Digits) > NormalizeDouble(MSMoveSpeed, global_Digits)) ){
            return BUY_SIGNAL;
         }

         //デッドクロスの時、移動速度が-moveSpeed(points/minutes)以下なら、売り。→デッドクロスが発生した直後を条件とすると厳しいので、GCがDCより遠いことで良しとする。
         if( ( (lastGC_MA > lastDC_MA && lastDC_MA >= 0) || (lastGC_MACD > lastDC_MACD && lastGC_MACD >= 0))
               &&
             (NormalizeDouble(MSSpeed*(-1.0), global_Digits) > NormalizeDouble(MSMoveSpeed, global_Digits)) ){
            return SELL_SIGNAL;   
         }
      }

      // 1:スピードの正負のみ。2:MAとMACDどちらかのGCやDCが条件を満たす。3:MAとMACD両方のGCやDCが条件を満たす。
      if(MSJUDGELEVEL == 3) {
         //ゴールデンクロスの時、移動速度が+moveSpeed(points/minutes)より大きければ、買い。→ゴールデンクロスが発生した直後を条件とすると厳しいので、GCがDCより近いことで良しとする。
         if( ( (lastGC_MA < lastDC_MA && lastGC_MA >= 0) && (lastGC_MACD < lastDC_MACD && lastGC_MACD >= 0))
               &&
             (NormalizeDouble(MSSpeed, global_Digits) > NormalizeDouble(MSMoveSpeed, global_Digits)) ){
            return BUY_SIGNAL;
         }

         //デッドクロスの時、移動速度が-moveSpeed(points/minutes)以下なら、売り。→デッドクロスが発生した直後を条件とすると厳しいので、GCがDCより遠いことで良しとする。
         if( ( (lastGC_MA > lastDC_MA && lastDC_MA >= 0) && (lastGC_MACD > lastDC_MACD && lastGC_MACD >= 0))
               &&
             (NormalizeDouble(MSSpeed*(-1.0), global_Digits) > NormalizeDouble(MSMoveSpeed, global_Digits)) ){
            return SELL_SIGNAL;   
         }
      }
      
   }   

   return NO_SIGNAL;
}