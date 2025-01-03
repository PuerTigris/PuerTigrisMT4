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
int CORREL_TF_SHORTER = 1;   //0から9。2は、PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
int CORREL_TF_LONGER  = 5;   //0から9。PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
double CORRELHigher   = 0.3; //-1.0～+1.0
double CORRELLower    = -0.9;//-1.0～+1.0
int CORREL_period     = 500;
*/
datetime Last_CORREL_TIMEtime0  = 0; // 不要なgetCORREL_TIMESの実行をしないための前回実行時間
datetime Last_CORREL_TIMEtime1  = 0; // 不要なgetCORREL_TIMESの実行をしないための前回実行時間
double globalCorrel_0  = DOUBLE_VALUE_MIN; // 不要なgetCORREL_TIMESの実行をしないため、大域変数で前回計算結果を保存する。
                                           // 初期値は、相関係数がとりえない値の-9999.9。
double globalCorrel_1  = DOUBLE_VALUE_MIN; // 不要なgetCORREL_TIMESの実行をしないため、大域変数で前回計算結果を保存する。
                                           // 初期値は、相関係数がとりえない値の-9999.9。

//+------------------------------------------------------------------+
//| No.18 相関係数を使った売買判定　　　　                      　      |
//+------------------------------------------------------------------+
int orderByCORREL_TIME(){
   int mSignal = NO_SIGNAL;
   
   // 外部パラメータCORRELHigher、CORRELLowerは相関係数のため、絶対値が1以上の場合は、何もしない。
   if(MathAbs(CORRELHigher) >= 1.0 || MathAbs(CORRELLower) >= 1.0) {
      return NO_SIGNAL;
   }
   // 外部パラメータCORRELHigher<=CORRELLowerの場合は、何もしない。
   if(CORRELHigher <= CORRELLower) {
      return NO_SIGNAL;
   }
   
   int CORREL_TF_SHORTER_local = getTimeFrame(CORREL_TF_SHORTER); // 外部パラメーターCORREL_TF_SHORTER(0-9)をgetTimeFrameで変換した値。
   int CORREL_TF_LONGER_local  = getTimeFrame(CORREL_TF_LONGER); // 外部パラメーターCORREL_TF_LONGER(0-9)をgetTimeFrameで変換した値。
   
   //CORREL_TF_SHORTERとCORREL_TF_LONGERが異常値の場合は何もしない
   if(CORREL_TF_SHORTER_local >= CORREL_TF_LONGER_local) {
     return NO_SIGNAL;
   }
   
   
   int longerTF = 0;
   int shorterTF = 0;

/*   //長い足と短い足を判断する。 
   if(CORREL_TF_SHORTER_local > CORREL_TF_LONGER_local) {
      longerTF  = CORREL_TF_SHORTER_local; // PERIOD_M1などENUM_TIMEFRAMES型
      shorterTF = CORREL_TF_LONGER_local;  // PERIOD_M1などENUM_TIMEFRAMES型
   }
   else {
      longerTF  = CORREL_TF_LONGER_local;
      shorterTF = CORREL_TF_SHORTER_local;
   }*/

   longerTF  = CORREL_TF_LONGER_local;
   shorterTF = CORREL_TF_SHORTER_local;

   
   //TimeFrame-TF1とTF2の相関係数を求める。
   // 前回計算時間Last_CORREL_TIMEtime0が0（＝初回計算）、
   // 又は、現在時間と前回計算時間の差が短い方のタイムフレームの時間間隔より長ければ、再計算をする。
   datetime dateTimeNow = Time[0];
//printf( "[%d]テスト　dateTimeNow - Last_CORREL_TIMEtime0=%s vs shorterTF=%d" , __LINE__ , IntegerToString(dateTimeNow - Last_CORREL_TIMEtime0), shorterTF);
   
   if( Last_CORREL_TIMEtime0 == 0 ||
       (dateTimeNow - Last_CORREL_TIMEtime0 > shorterTF) ){
      //
      // 計算起点をシフト0として時間軸間の相関係数を計算する
      // 
      getCORREL_TIMES(longerTF,   // 相関係数を計算する長い方の時間軸。PERIOD_M1などENUM_TIMEFRAMES型
                      shorterTF,  // 相関係数を計算する短い方の時間軸。PERIOD_M1などENUM_TIMEFRAMES型
                      CORREL_period, // 相関係数を計算するデータ件数
                      globalCorrel_0,// シフト0を起点とするデータを使った相関係数。この関数の返り値でもある。 
                      globalCorrel_1 // シフト1を起点とするデータを使った相関係数
                      );

/*printf( "[%d]CORREL globalCorrel_0=%s  globalCorrel_1=%s"  , __LINE__,
DoubleToStr(globalCorrel_0, global_Digits),
DoubleToStr(globalCorrel_1, global_Digits)
);*/      
      if(MathAbs(NormalizeDouble(globalCorrel_0, global_Digits)) > 1.0000) {
         return NO_SIGNAL;  //相関係数が1より大きい場合は異常値のため以降の処理を中断する。
      }
      else {
//printf( "[%d]テスト　Last_CORREL_TIMEtime0%s -> %s globalCorrel_0を更新 %s" , __LINE__ , TimeToStr(Last_CORREL_TIMEtime0),TimeToStr(dateTimeNow), DoubleToStr(globalCorrel_0));
         Last_CORREL_TIMEtime0 = dateTimeNow;
      }
   }

   
   //相関係数がCORRELHigherより大きくなった時か、CORRELLowerより小さくなった時オーダーする。
   if( (NormalizeDouble(globalCorrel_1, global_Digits) < NormalizeDouble(CORRELHigher, global_Digits) 
        && NormalizeDouble(globalCorrel_0, global_Digits) > NormalizeDouble(CORRELHigher, global_Digits) )
        ||
       (NormalizeDouble(globalCorrel_1, global_Digits) > NormalizeDouble(CORRELLower , global_Digits) 
        && NormalizeDouble(globalCorrel_0, global_Digits) < NormalizeDouble(CORRELLower, global_Digits)) ) {

      //戦略：相関係数が正の時、短い足は長い足に引き寄せられる。負の時、短い足は長い足から離れる。
      double longerClose1  = iClose(global_Symbol,longerTF,1);
      double shorterClose1 = iClose(global_Symbol,shorterTF,1);
      if(longerClose1 <= 0.0) {
         return NO_SIGNAL;
      }
      if(shorterClose1 <= 0.0) {
     
         return NO_SIGNAL;
      }

      if(globalCorrel_0 > 0.0) {
         //長い足(longerTF)のClose[1]より短い足(shorterTF)の方が小さい場合、買いオーダー
         if(NormalizeDouble(longerClose1, global_Digits) >= NormalizeDouble(shorterClose1, global_Digits) ) {
            mSignal = BUY_SIGNAL;
         }
         //長い足(longerTF)のClose[1]より短い足(shorterTF)の方が大きい場合、売りオーダー
         else if(NormalizeDouble(longerClose1, global_Digits) < NormalizeDouble(shorterClose1, global_Digits) ) {
            mSignal = SELL_SIGNAL;
         }
         else {
            return NO_SIGNAL;
         }
      }
      else if(globalCorrel_0 < 0.0) {
         //長い足(longerTF)のClose[1]より短い足(shorterTF)の方が小さい場合、値の大きい長い足から離れようとしていることから、売りオーダー
         if(NormalizeDouble(longerClose1, global_Digits) >= NormalizeDouble(shorterClose1, global_Digits) ) {
            mSignal = SELL_SIGNAL;
         }
         //長い足(longerTF)のClose[1]より短い足(shorterTF)の方が大きい場合、売りオーダー
         else if(NormalizeDouble(longerClose1, global_Digits) < NormalizeDouble(shorterClose1, global_Digits) ) {
            mSignal = BUY_SIGNAL;
         }
         else {
            return NO_SIGNAL;
         }
      }      
   }
   

   if(mSignal == BUY_SIGNAL) {
      // ロングしたいが下落トレンドであれば、シグナル消滅
      if(get_Trend_Alligator(global_Symbol, global_Period, 1) == DownTrend) {
      
         mSignal = NO_SIGNAL;
      }
   }
   else if(mSignal == SELL_SIGNAL) {
      // ショートしたいが下落トレンドであれば、シグナル消滅
      if(get_Trend_Alligator(global_Symbol, global_Period, 1) == UpTrend) {
         mSignal = NO_SIGNAL;
      }
   }   
   return mSignal;
}



int orderByCORREL_TIME_Shift(int mTimeframe, int mShift){
   int mSignal = NO_SIGNAL;
   
   // 外部パラメータCORRELHigher、CORRELLowerは相関係数のため、絶対値が1以上の場合は、何もしない。
   if(MathAbs(CORRELHigher) >= 1.0 || MathAbs(CORRELLower) >= 1.0) {
      return NO_SIGNAL;
   }
   // 外部パラメータCORRELHigher<=CORRELLowerの場合は、何もしない。
   if(CORRELHigher <= CORRELLower) {
      return NO_SIGNAL;
   }
   
   int CORREL_TF_SHORTER_local = getTimeFrame(CORREL_TF_SHORTER); // 外部パラメーターCORREL_TF_SHORTER(0-9)をgetTimeFrameで変換した値。
   int CORREL_TF_LONGER_local  = getTimeFrame(CORREL_TF_LONGER); // 外部パラメーターCORREL_TF_LONGER(0-9)をgetTimeFrameで変換した値。
   
   //CORREL_TF_SHORTERとCORREL_TF_LONGERが異常値の場合は何もしない
   if(CORREL_TF_SHORTER_local >= CORREL_TF_LONGER_local) {
     return NO_SIGNAL;
   }
   
   
   int longerTF  = 0;
   int shorterTF = 0;

/*   //長い足と短い足を判断する。 
   if(CORREL_TF_SHORTER_local > CORREL_TF_LONGER_local) {
      longerTF  = CORREL_TF_SHORTER_local; // PERIOD_M1などENUM_TIMEFRAMES型
      shorterTF = CORREL_TF_LONGER_local;  // PERIOD_M1などENUM_TIMEFRAMES型
   }
   else {
      longerTF  = CORREL_TF_LONGER_local;
      shorterTF = CORREL_TF_SHORTER_local;
   }
*/

   longerTF  = CORREL_TF_LONGER_local;
   shorterTF = CORREL_TF_SHORTER_local;
   
   //TimeFrame-TF1とTF2の相関係数を求める。
   // 前回計算時間Last_CORREL_TIMEtime0が0（＝初回計算）、
   // 又は、現在時間と前回計算時間の差が短い方のタイムフレームの時間間隔より長ければ、再計算をする。
   datetime dateTimeNow = Time[0];
   
   if( Last_CORREL_TIMEtime0 == 0 ||
       (dateTimeNow - Last_CORREL_TIMEtime0 > shorterTF) ){
      //
      // 計算起点をシフトmShiftとして時間軸間の相関係数を計算する
      // 
      getCORREL_TIMES(longerTF,   // 相関係数を計算する長い方の時間軸。PERIOD_M1などENUM_TIMEFRAMES型
                      shorterTF,  // 相関係数を計算する短い方の時間軸。PERIOD_M1などENUM_TIMEFRAMES型
                      CORREL_period, // 相関係数を計算するデータ件数
                      mShift,     // 相関係数を計算する起点となるシフト
                      globalCorrel_0,// シフトmShift  を起点とするデータを使った相関係数。この関数の返り値でもある。 
                      globalCorrel_1 // シフトmShift+1を起点とするデータを使った相関係数
                      );

      if(MathAbs(NormalizeDouble(globalCorrel_0, global_Digits)) > 1.0000) {
         return NO_SIGNAL;  //相関係数が1より大きい場合は異常値のため以降の処理を中断する。
      }
      else {
         Last_CORREL_TIMEtime0 = dateTimeNow;
      }
   }

   
   //相関係数がCORRELHigherより大きくなった時か、CORRELLowerより小さくなった時オーダーする。
   if( (NormalizeDouble(globalCorrel_1, global_Digits) < NormalizeDouble(CORRELHigher, global_Digits) 
        && NormalizeDouble(globalCorrel_0, global_Digits) > NormalizeDouble(CORRELHigher, global_Digits) )
        ||
       (NormalizeDouble(globalCorrel_1, global_Digits) > NormalizeDouble(CORRELLower , global_Digits) 
        && NormalizeDouble(globalCorrel_0, global_Digits) < NormalizeDouble(CORRELLower, global_Digits)) ) {

      //戦略：相関係数が正の時、短い足は長い足に引き寄せられる。負の時、短い足は長い足から離れる。
      double longerClose1  = iClose(global_Symbol, longerTF,  mShift + 1);
      double shorterClose1 = iClose(global_Symbol, shorterTF, mShift + 1);
      if(longerClose1 <= 0.0) {
         return NO_SIGNAL;
      }
      if(shorterClose1 <= 0.0) {
         return NO_SIGNAL;
      }

      if(globalCorrel_0 > 0.0) {
         //長い足(longerTF)のClose[1]より短い足(shorterTF)の方が小さい場合、買いオーダー
         if(NormalizeDouble(longerClose1, global_Digits) >= NormalizeDouble(shorterClose1, global_Digits) ) {
            mSignal = BUY_SIGNAL;
         }
         //長い足(longerTF)のClose[1]より短い足(shorterTF)の方が大きい場合、売りオーダー
         else if(NormalizeDouble(longerClose1, global_Digits) < NormalizeDouble(shorterClose1, global_Digits) ) {
            mSignal = SELL_SIGNAL;
         }
         else {
            return NO_SIGNAL;
         }
      }
      else if(globalCorrel_0 < 0.0) {
         //長い足(longerTF)のClose[1]より短い足(shorterTF)の方が小さい場合、値の大きい長い足から離れようとしていることから、売りオーダー
         if(NormalizeDouble(longerClose1, global_Digits) >= NormalizeDouble(shorterClose1, global_Digits) ) {
            mSignal = SELL_SIGNAL;
         }
         //長い足(longerTF)のClose[1]より短い足(shorterTF)の方が大きい場合、売りオーダー
         else if(NormalizeDouble(longerClose1, global_Digits) < NormalizeDouble(shorterClose1, global_Digits) ) {
            mSignal = BUY_SIGNAL;
         }
         else {
            return NO_SIGNAL;
         }
      }      
   }

   // トレンド判断は、mTimeframe又はlongerTFの長い方できめる
   if(mTimeframe < longerTF) {
      mTimeframe = longerTF;
   }
   if(mSignal == BUY_SIGNAL) {
      // ロングしたいが下落トレンドであれば、シグナル消滅
      if(get_Trend_Alligator(global_Symbol, mTimeframe, mShift + 1) == DownTrend) {
         mSignal = NO_SIGNAL;
      }
   }
   else if(mSignal == SELL_SIGNAL) {
      // ショートしたいが下落トレンドであれば、シグナル消滅
      if(get_Trend_Alligator(global_Symbol, mTimeframe,  mShift + 1) == UpTrend) {
         mSignal = NO_SIGNAL;
      }
   }   

   return mSignal;
}


//
// 計算起点をシフト0として時間軸間の相関係数を計算する
// 
double getCORREL_TIMES(int mTF1, // PERIOD_M1などENUM_TIMEFRAMES型
                       int mTF2, // PERIOD_M1などENUM_TIMEFRAMES型
                       int data_num, // 相関係数を計算するデータ件数
                       double &outputShift0,  // シフト0を起点とするデータを使った相関係数。この関数の返り値でもある。
                       double &outputShift1   // シフト1を起点とするデータを使った相関係数
                   ) {

   if(data_num > 1000) return ERROR_VALUE_DOUBLE;
   
   // mTF1が、PERIOD_M1などENUM_TIMEFRAMES型出なければ、エラー
   if(checkTimeFrame(mTF1) == false) return ERROR_VALUE_DOUBLE;
   
   // mTF2が、PERIOD_M1などENUM_TIMEFRAMES型出なければ、エラー
   if(checkTimeFrame(mTF2) == false) return ERROR_VALUE_DOUBLE;
   
   double CORRELtime_dat1[10000];
   double CORRELtime_dat2[10000];
   double bufCORRELtime_dat1[10000];
   double bufCORRELtime_dat2[10000];
   
   
   //配列の初期化
   ArrayInitialize(CORRELtime_dat1,0.0);
   ArrayInitialize(CORRELtime_dat2,0.0);

   int i;
   //各配列に移動平均値を読み込む
   for(i = 0; i <= data_num; i++) {
     CORRELtime_dat1[i] = iMA(global_Symbol,mTF1,25,0,MODE_SMA,PRICE_CLOSE,i);
     CORRELtime_dat2[i] = iMA(global_Symbol,mTF2,25,0,MODE_SMA,PRICE_CLOSE,i);
   }
   
   //相関係数を計算する。
   //シフト0の時。 CORRELtime_dat1とCORRELtime_dat2の0～(data_num-1)番目を使う。
   double correl_val_Shift0 = ERROR_VALUE_DOUBLE;
   ArrayInitialize(bufCORRELtime_dat1,0.0);
   ArrayInitialize(bufCORRELtime_dat2,0.0);   
   for(i = 0; i < data_num; i++) {
      bufCORRELtime_dat1[i] = CORRELtime_dat1[i];
      bufCORRELtime_dat2[i] = CORRELtime_dat2[i];
   }
   correl_val_Shift0 = CORREL(bufCORRELtime_dat1, bufCORRELtime_dat2, data_num);
//printf( "[%d]CORREL correl_val_Shift0=%s" , __LINE__, DoubleToStr(correl_val_Shift0, global_Digits) );         

   //シフト1の時。 CORRELtime_dat1とCORRELtime_dat2の1～(data_num)番目を使う。
   double correl_val_Shift1 = ERROR_VALUE_DOUBLE;
   ArrayInitialize(bufCORRELtime_dat1,0.0);
   ArrayInitialize(bufCORRELtime_dat2,0.0);
   
   for(i = 1; i < data_num+1; i++) {
      bufCORRELtime_dat1[i-1] = CORRELtime_dat1[i];
      bufCORRELtime_dat2[i-1] = CORRELtime_dat2[i];
   }
   correl_val_Shift1 = CORREL(bufCORRELtime_dat1, bufCORRELtime_dat2, data_num);
//printf( "[%d]CORREL correl_val_Shift1=%s" , __LINE__, DoubleToStr(correl_val_Shift1, global_Digits) );            
   //----
   outputShift0 = correl_val_Shift0;
   outputShift1 = correl_val_Shift1;
   return(correl_val_Shift0);
}


//
// 計算起点をシフトmShiftとして時間軸間の相関係数を計算する
// 
double getCORREL_TIMES(int mTF1, // PERIOD_M1などENUM_TIMEFRAMES型
                       int mTF2, // PERIOD_M1などENUM_TIMEFRAMES型
                       int data_num, // 相関係数を計算するデータ件数
                       int mShift,   // 相関係数を計算する起点となるシフト
                       double &outputShift0,  // シフト0を起点とするデータを使った相関係数。この関数の返り値でもある。
                       double &outputShift1   // シフト1を起点とするデータを使った相関係数
                   ) {

   if(data_num > 1000) return ERROR_VALUE_DOUBLE;
   
   // mTF1が、PERIOD_M1などENUM_TIMEFRAMES型出なければ、エラー
   if(checkTimeFrame(mTF1) == false) return ERROR_VALUE_DOUBLE;
   
   // mTF2が、PERIOD_M1などENUM_TIMEFRAMES型出なければ、エラー
   if(checkTimeFrame(mTF2) == false) return ERROR_VALUE_DOUBLE;
   
   double CORRELtime_dat1[10000];
   double CORRELtime_dat2[10000];
   double bufCORRELtime_dat1[10000];
   double bufCORRELtime_dat2[10000];
   
   
   //配列の初期化
   ArrayInitialize(CORRELtime_dat1,0.0);
   ArrayInitialize(CORRELtime_dat2,0.0);

   int i;
   //各配列に移動平均値を読み込む
   for(i = 0; i <= data_num; i++) {
     CORRELtime_dat1[i] = iMA(global_Symbol,mTF1,25,0,MODE_SMA,PRICE_CLOSE, mShift + i);
     CORRELtime_dat2[i] = iMA(global_Symbol,mTF2,25,0,MODE_SMA,PRICE_CLOSE, mShift + i);
   }
   
   //相関係数を計算する。
   //シフト0の時。 CORRELtime_dat1とCORRELtime_dat2の0～(data_num-1)番目を使う。
   double correl_val_Shift0 = ERROR_VALUE_DOUBLE;
   ArrayInitialize(bufCORRELtime_dat1,0.0);
   ArrayInitialize(bufCORRELtime_dat2,0.0);   
   for(i = 0; i < data_num; i++) {
      bufCORRELtime_dat1[i] = CORRELtime_dat1[i];
      bufCORRELtime_dat2[i] = CORRELtime_dat2[i];
   }
   correl_val_Shift0 = CORREL(bufCORRELtime_dat1, bufCORRELtime_dat2, data_num);

   //シフト1の時。 CORRELtime_dat1とCORRELtime_dat2の1～(data_num)番目を使う。
   double correl_val_Shift1 = ERROR_VALUE_DOUBLE;
   ArrayInitialize(bufCORRELtime_dat1,0.0);
   ArrayInitialize(bufCORRELtime_dat2,0.0);
   
   for(i = 1; i < data_num+1; i++) {
      bufCORRELtime_dat1[i-1] = CORRELtime_dat1[i];
      bufCORRELtime_dat2[i-1] = CORRELtime_dat2[i];
   }
   correl_val_Shift1 = CORREL(bufCORRELtime_dat1, bufCORRELtime_dat2, data_num);
   //----
   outputShift0 = correl_val_Shift0;
   outputShift1 = correl_val_Shift1;
   return(correl_val_Shift0);
}

/*
double getCORREL_TIMES(int time1, int time2, int mShift, int data_num) {

    if(data_num > 1000) return 9999;

    if(checkTimeFrame(time1) == false) return 9999;

    if(checkTimeFrame(time2) == false) return 9999;

    double CORRELtime_dat1[1000];
    double CORRELtime_dat2[1000];

  
    //配列の初期化
    ArrayInitialize(CORRELtime_dat1,0.0);
    ArrayInitialize(CORRELtime_dat2,0.0);

    //各配列に終値を読み込む
    for(int i = 0; i < data_num; i++) {
        CORRELtime_dat1[i] = iMA(global_Symbol,time1,25,0,MODE_SMA,PRICE_CLOSE,i + mShift);
        CORRELtime_dat2[i] = iMA(global_Symbol,time2,25,0,MODE_SMA,PRICE_CLOSE,i + mShift);

    }
    
    //相関係数を計算する。
    double correl_val=CORREL(CORRELtime_dat1, CORRELtime_dat2, data_num);

    return(correl_val);
}
*/

//+------------------------------------------------------------------+
//|   相関係数を求める関数                                           |
//+------------------------------------------------------------------+
double CORREL(double &correl_dat1[],double &correl_dat2[], int data_num) {
    double ret=9999;
    double dat1_sum=0.0;
    double dat2_sum=0.0;
    double dat1_av=0.0;
    double dat2_av=0.0;
    int i;
    //各配列の合計値を計算する。
    for(i=0; i< data_num; i++) {
        dat1_sum += correl_dat1[i];
        dat2_sum += correl_dat2[i];
    }
 
    //各配列の平均値を計算する。
    dat1_av =dat1_sum / data_num;
    dat2_av =dat2_sum / data_num;

    double dat1_tmp=0.0;
    double dat2_tmp=0.0;
    double tmp=0.0;

    for(i = 0; i < data_num; i++) { 
        //分散を計算する。
        dat1_tmp += MathPow((correl_dat1[i]-dat1_av),2);
        dat2_tmp += MathPow((correl_dat2[i]-dat2_av),2);

        //共分散を計算する。
        tmp += (correl_dat1[i] - dat1_av) * (correl_dat2[i] - dat2_av);
    }

    //相関係数を計算する。
    double tmp2 = (MathPow(dat1_tmp,0.5) * MathPow(dat2_tmp,0.5));
    if(tmp2 == 0)return(DOUBLE_VALUE_MAX);
    else ret = tmp / (MathPow(dat1_tmp,0.5) * MathPow(dat2_tmp,0.5));

    return(ret);
}





