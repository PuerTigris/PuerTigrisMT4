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
#include <Tigris_Statistics.mqh>
//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	

datetime testMRAtime0 = 0;
struct st_checkPrice {  // 時間ごとの値段予測と実績値チェック用
   datetime targetTime;   // 基準時刻
   double   openPre;      // 予測始値
   double   highPre;      // 予測高値
   double   lowPre;       // 予測安値
   double   closePre;     // 予測終値
   double   openAct;      // 実際始値
   double   highAct;      // 実際高値
   double   lowAct;       // 実際安値
   double   closeAct;     // 実際終値
};
st_checkPrice st_checkPrices[9999];
//+------------------------------------------------------------------+
//|94.MRA-Multi-Regression-Analysis                                                 　　　   |
//+------------------------------------------------------------------+
//
// 重回帰分析を使って予測した直後のHigh/Lowデータと直近（＝シフト0）データOpenを比較して、
// 売買シグナルを発生させる。
// ・予測した直後のHighデータ - 直近（＝シフト0）データOpen >= TPであれば、ロング
//   ただし、上記を満たしているにもかかわらず、直近（＝シフト0）データOpen - 予測した直後のLowデータ >= SLの場合は、シグナル無し。
// ・直近（＝シフト0）データOpen - 予測した直後のLowデータ  >= TPであれば、ショート
//   ただし、上記を満たしているにもかかわらず、予測した直後のHighデータ - 直近（＝シフト0）データOpen >= SLの場合は、シグナル無し。

double nextData_High = DOUBLE_VALUE_MIN;
double nextData_Low = DOUBLE_VALUE_MIN;
datetime last_calc_Time = 0; // 直前に、直近の高値、安値を計算した時刻
int entryMRA() {
   // 次数が1以下の時は計算しない。
   if(MRA_DEGREE <= 1) {
      return NO_SIGNAL;
   }
   
   string local_symbol = Symbol();
   int i = 0;
   double slope[MAX_MRA_DEGREE];
   double intercept = 0;
   //int i;

   int timeframe = Period(); // getTimeFrame(MRA_TIMEFRAME_NO);
   int datanum   = MRA_DATA_NUM;

   // TYPE_CLOSEの直近データ(シフト0)を取得する。
   double lastData = get_EachTypeValue(TYPE_CLOSE,// 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                       timeframe,// 取得するデータの時間軸。
                                       0         // 取得するデータのシフト。
                                       );                                    

   if(TimeCurrent() - last_calc_Time > Time[1] - Time[2]) {
      //
      // 重回帰分析を使って、TYPE_HIGH、TYPE_LOWの値を予測する。
      //
   
     // 重回帰分析を使った、直後データの予測
      calc_NextData_MRA_VariousData(TYPE_HIGH, // データの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                        timeframe,             // 取得するデータの時間軸。
                        MRA_EXP_TYPE,          // 説明変数のデータパターン　1-7 1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, slopeH4
                        datanum,               // 予測に使用するデータ件数
                        nextData_High          // 出力：直後のデータ
                       );
                          
   
   
      // 重回帰分析を使った、直後データの予測
      calc_NextData_MRA_VariousData(TYPE_LOW,  // データの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                        timeframe,             // 取得するデータの時間軸。
                        MRA_EXP_TYPE,          // 説明変数のデータパターン　1-7 1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, slopeH4
                        datanum,               // 予測に使用するデータ件数
                        nextData_Low           // 出力：直後のデータ
                       );
      last_calc_Time = TimeCurrent(); 
   }
   else {
   }

   // 高値予測値と安値予測値が逆転している場合は、予測精度が落ちているため、処理を中断。
   if(nextData_Low > nextData_High) {
      return NO_SIGNAL;
   }

   datetime nowDatetime = iTime(local_symbol, timeframe, 0);
   datetime diffTime = Time[1] - Time[2];   
   double tmpHigh = 0.0;
   double tmpLow  = 0.0;
   put_st_checkPrices_Pre(nowDatetime + diffTime, 0.0, nextData_High, nextData_Low, 0.0);
   testMRAtime0 = nowDatetime;  
/*      
datetime nowDatetime = iTime(local_symbol, timeframe, 0);
MqlDateTime cjtm; // 時間構造体
TimeToStruct(nowDatetime, cjtm); // 構造体の変数に変換
datetime diffTime = Time[0] - Time[1];
//if(cjtm.min == 0 && cjtm.sec == 0) {
if(MathAbs(nowDatetime - TimeCurrent()) == 5 * 60) {
   if(testMRAtime0 != nowDatetime) {
      printf("[%d]MRA %s, %d, 予測データ, 時間, High, Low, %s, %s, %s, 実績データ, %s, %s, %s, Open=%s, Close=%s", __LINE__, 
               local_symbol,timeframe,
               TimeToString(nowDatetime + diffTime) , DoubleToStr(nextData_High, 5), DoubleToStr(nextData_Low, 5),
               TimeToString(iTime(local_symbol, timeframe, 1)) , DoubleToStr(iHigh(local_symbol, timeframe, 1), 5), DoubleToStr(iLow(local_symbol, timeframe, 1), 5),
               DoubleToStr(iOpen(local_symbol, timeframe, 1), 5), DoubleToStr(iClose(local_symbol, timeframe, 1), 5)
              );
double tmpHigh = 0.0;
double tmpLow  = 0.0;
      put_st_checkPrices_Pre(nowDatetime + diffTime, 0.0, nextData_High, nextData_Low, 0.0);
      testMRAtime0 = nowDatetime;    
   }
}
*/
/*
printf("[%d]MRA %sのシグナル判断 lastData=%s,  nextData_High=%s, nextData_Low=%s", __LINE__, 
        TimeToStr(TimeCurrent()),
        DoubleToString(lastData, 5),
        DoubleToString(nextData_High, 5),
        DoubleToString(nextData_Low, 5)
        );
*/
/****/
   // シグナルの判断
   // ・予測した直後のLowデータ及びHighデータから、直近終値（＝シフト0）の差額のどちらかが、正で、絶対値がTP以上の場合は、買い
   //   ただし、予測した直後のLowデータ及びHighデータから、直近終値（＝シフト0）の差額のどちらかが、負で、絶対値がSL以上の場合は、シグナル取り消し
   // ・直近終値（＝シフト0）から、予測した直後のLowデータ及びHighデータの差額のどちらかが、正で、絶対値がTP以上の場合は、売り
   //   ただし、直近終値（＝シフト0）から、予測した直後のLowデータ及びHighデータの差額のどちらかが、負で、絶対値がSL以上の場合は、シグナル取り消し
   double diff_Point_Loss = 0.0; // 予測値と直近値の差分。単位はポイント
   double diff_Point_Profit = 0.0; // 予測値と直近値の差分。単位はポイント
   double diff_Next_High_Point = 0.0; // 高値予測値と直近値の差分。単位はポイント
   double diff_Next_Low_Point = 0.0;  // 安値予測値と直近値の差分。単位はポイント
//printf("[%d]MRA.mqh 時間計測用--買いシグナル判定開始", __LINE__);
   
   //
   // 高値予測値と安値予測値を使ったシグナル判定をする。
   // 高値予測値 < 安値予測値が発生した場合は、事前に処理中断しているため、以降では考慮不要。
   //

   // 
   // 買いシグナルの判断
   // 
   bool buySignal = false;

   // 高値予測値と直近始値の差額、安値予測値と直近始値の差額
   diff_Next_High_Point = nextData_High - lastData;
   diff_Next_Low_Point  = nextData_Low  - lastData;


   // 予測した直後のLowデータ及びHighデータから、直近終値（＝シフト0）の差額のどちらかが、負で、絶対値がSL以上の場合は、買いシグナル取り消し
   if(  (diff_Next_High_Point < 0.0 && change_Point2PIPS(local_symbol, MathAbs(diff_Next_High_Point)) >= MRA_SL_PIPS) 
        ||
        (diff_Next_Low_Point  < 0.0 && change_Point2PIPS(local_symbol, MathAbs(diff_Next_Low_Point))  >= MRA_SL_PIPS)      ) {
      buySignal = false;
   }
   // 予測した直後のLowデータ及びHighデータから、直近終値（＝シフト0）の差額のどちらかが、正で、絶対値がTP以上の場合は、買い
   else {
      if(  (diff_Next_High_Point > 0.0 && change_Point2PIPS(local_symbol, MathAbs(diff_Next_High_Point)) >= MRA_TP_PIPS) 
           &&
           (diff_Next_Low_Point  > 0.0 && change_Point2PIPS(local_symbol, MathAbs(diff_Next_Low_Point))  >= MRA_TP_PIPS)    ) {
      buySignal = true;
      }
   }

   // 
   // 売りシグナルの判断
   // 
   bool sellSignal = false;
   
   // 高値予測値と直近始値の差額、安値予測値と直近始値の差額
   diff_Next_High_Point = lastData - nextData_High;
   diff_Next_Low_Point  = lastData - nextData_Low;


   // 直近終値（＝シフト0）から予測した直後のLowデータ及びHighデータの差額のどちらかが、負で、絶対値がSL以上の場合は、買いシグナル取り消し
   if(  (diff_Next_High_Point < 0.0 && change_Point2PIPS(local_symbol, MathAbs(diff_Next_High_Point)) >= MRA_SL_PIPS) 
        ||
        (diff_Next_Low_Point  < 0.0 && change_Point2PIPS(local_symbol, MathAbs(diff_Next_Low_Point))  >= MRA_SL_PIPS)      ) {
      sellSignal = false;
   }
   // 直近終値（＝シフト0）から予測した直後のLowデータ及びHighデータの差額のどちらかが、正で、絶対値がTP以上の場合は、買い
   else {
      if(  (diff_Next_High_Point > 0.0 && change_Point2PIPS(local_symbol, MathAbs(diff_Next_High_Point)) >= MRA_TP_PIPS) 
           &&
           (diff_Next_Low_Point  > 0.0 && change_Point2PIPS(local_symbol, MathAbs(diff_Next_Low_Point))  >= MRA_TP_PIPS)    ) {
      sellSignal = true;
      }
   }

   int retBuySellSignal = NO_SIGNAL;
   int trend = get_Trend_EMA_PERIODH4(timeframe, 0);
   if(buySignal == true && trend == UpTrend) {
      retBuySellSignal = BUY_SIGNAL;
   }
   else if(sellSignal == true && trend == DownTrend) {
      retBuySellSignal = SELL_SIGNAL;
   }
   else {
      retBuySellSignal = NO_SIGNAL;
   }   


   return retBuySellSignal;

}


void init_st_checkPrices() {
   int i;
   for(i = 0; i < 9999; i++) {
      st_checkPrices[i].targetTime = 0;
      st_checkPrices[i].openPre  = DOUBLE_VALUE_MIN;
      st_checkPrices[i].highPre  = DOUBLE_VALUE_MIN;
      st_checkPrices[i].lowPre   = DOUBLE_VALUE_MIN;
      st_checkPrices[i].closePre = DOUBLE_VALUE_MIN;
      st_checkPrices[i].openAct  = DOUBLE_VALUE_MIN;
      st_checkPrices[i].highAct  = DOUBLE_VALUE_MIN;
      st_checkPrices[i].lowAct   = DOUBLE_VALUE_MIN;
      st_checkPrices[i].closeAct = DOUBLE_VALUE_MIN;
   }
}


void put_st_checkPrices_Pre(datetime mTargetTime, 
                            double   mOpen,
                            double   mHigh,
                            double   mLow,
                            double   mClose) {
   int i;
   for(i = 0; i < 9999; i++) {
      if(st_checkPrices[i].targetTime <= 0 || st_checkPrices[i].targetTime == mTargetTime) {
         st_checkPrices[i].targetTime = mTargetTime;
         st_checkPrices[i].openPre    = mOpen;
         st_checkPrices[i].highPre    = mHigh;
         st_checkPrices[i].lowPre     = mLow;
         st_checkPrices[i].closePre   = mClose;
         break;
      }
   }
}

void update_st_checkPrices_Act() {
//   datetime mTargetTime;
   double   mOpen;
   double   mHigh;
   double   mLow;
   double   mClose;
   int i;
   for(i = 0; i < 9999; i++) {
      if(st_checkPrices[i].targetTime <= 0) {
         break;
      }
      get_4PricesByTime(Symbol(), 
                        st_checkPrices[i].targetTime, 
                        st_checkPrices[i].targetTime+60, 
                        mOpen, 
                        mHigh,
                        mLow,
                        mClose);
      st_checkPrices[i].openAct    = mOpen;
      st_checkPrices[i].highAct    = mHigh;
      st_checkPrices[i].lowAct     = mLow;
      st_checkPrices[i].closeAct   = mClose;
   }
}


/*
// 直後以降の予測値を使っていた当時のentryMRA()。
// 直後以降の予測値を計算できないため、廃止。
int orgentryMRA() {
   // 次数が1以下の時は計算しない。
   if(MRA_DEGREE <= 1) {
      return NO_SIGNAL;
   }
   
   string local_symbol = Symbol();
   int i = 0;
   double slope[MAX_MRA_DEGREE];
   double intercept = 0;
   //int i;

   int timeframe = Period(); // getTimeFrame(MRA_TIMEFRAME_NO);
 //  int degree  = MRA_DEGREE;
   int datanum = MRA_DATA_NUM;

   // TYPE_OPENの直近データ(シフト0)を取得する。
   double lastData = get_EachTypeValue(TYPE_CLOSE,// 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                       timeframe,// 取得するデータの時間軸。
                                       0         // 取得するデータのシフト。
                                       );                                    

// printf("[%d]MRA.mqh 時間計測用--HIGH予測開始", __LINE__);
   //
   // 重回帰分析を使って、TYPE_HIGH、TYPE_LOWの値を予測する。
   //
   double nextData_High = DOUBLE_VALUE_MIN;
  // 重回帰分析を使った、直後データの予測
   calc_NextData_MRA_VariousData(TYPE_HIGH, // データの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                     timeframe, // 取得するデータの時間軸。
                     1,
                     datanum,                     
                     nextData_High   // 出力：直後のデータ
                    );


   double futureData_High[MAX_MRA_EXP_DATA_NUM];  // 複数の将来値を取得する実験用配列
   calc_NextData_MRA_VariousData(TYPE_HIGH,  // データの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                     timeframe, // 取得するデータの時間軸。
                     1,
                     datanum,                     
                     futureData_High   // 出力：将来のデータ
                    ); 

   if(futureData_High[0] != nextData_High) {
      printf("[%d]MRA.mqh 将来値エラー　1つのみ計算=>%s<  複数計算=>%s<", __LINE__, 
             DoubleToString(nextData_High, 6),
             DoubleToString(futureData_High[0], 6)
            );      
   }
   else {
      printf("[%d]MRA.mqh 高値将来値一致　1つのみ計算=>%s<  複数計算=>%s<", __LINE__, 
             DoubleToString(nextData_High, 6),
             DoubleToString(futureData_High[0], 6)
            );      
   }

                       
   double nextData_Low = DOUBLE_VALUE_MIN;
   // 重回帰分析を使った、直後データの予測
   calc_NextData_MRA_VariousData(TYPE_LOW,  // データの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                     timeframe, // 取得するデータの時間軸。
                     1,
                     datanum,                     
                     nextData_Low   // 出力：直後のデータ
                    );

   double futureData_Low[MAX_MRA_EXP_DATA_NUM];  // 複数の将来値を取得する実験用配列
   calc_NextData_MRA_VariousData(TYPE_LOW,  // データの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                     timeframe, // 取得するデータの時間軸。
                     1,
                     datanum,                     
                     futureData_Low   // 出力：将来のデータ
                    );   

                                                                 
//printf("[%d]MRA.mqh 時間計測用--LOW予測終了", __LINE__);
   if(futureData_Low[0] != nextData_Low) {
      printf("[%d]MRA.mqh 将来値エラー　1つのみ計算=>%s<  複数計算=>%s<", __LINE__, 
             DoubleToString(nextData_Low, 6),
             DoubleToString(futureData_Low[0], 6)
            );      
   }
   else {
      printf("[%d]MRA.mqh 安値将来値一致　1つのみ計算=>%s<  複数計算=>%s<", __LINE__, 
             DoubleToString(nextData_Low, 6),
             DoubleToString(futureData_Low[0], 6)
            );  
   }
   

   // 高値予測値と安値予測値が逆転している場合は、予測精度が落ちているため、処理を中断。
   if(nextData_Low > nextData_High) {
      return NO_SIGNAL;
   }


//   printf("[%d]STA 1つだけ計算したnextData_Low=%s", __LINE__, DoubleToString(nextData_Low, 6));   
//   for(int i = 0; i < degree; i++) {
//      printf("[%d]STA 同時に複数計算した計算したnextData_Low=%s", __LINE__, DoubleToString(test[i], 6));   
//   }

if(Time[0] == TimeCurrent() ) {
printf("[%d]MRA 予測データ, 時間, High, Low, %s,%s, %s", __LINE__, TimeToString(Time[0]) , DoubleToStr(futureData_High[0], 5), DoubleToStr(futureData_Low[0], 5));   
}

   // シグナルの判断
   // ・予測した直後のHighデータ - 直近（＝シフト0）データOpen >= TPであれば、ロング
   //   ただし、上記を満たしているにもかかわらず、直近（＝シフト0）データOpen - 予測した直後のLowデータ >= SLの場合は、シグナル取り消し
   // ・直近（＝シフト0）データOpen - 予測した直後のLowデータ  >= TPであれば、ショート
   //   ただし、上記を満たしているにもかかわらず、予測した直後のHighデータ - 直近（＝シフト0）データOpen >= SLの場合は、シグナル無し。
   double diff_Point_Loss = 0.0; // 予測値と直近値の差分。単位はポイント
   double diff_Point_Profit = 0.0; // 予測値と直近値の差分。単位はポイント
   double diff_Next_High_Point = 0.0; // 高値予測値と直近値の差分。単位はポイント
   double diff_Next_Low_Point = 0.0;  // 安値予測値と直近値の差分。単位はポイント
//printf("[%d]MRA.mqh 時間計測用--買いシグナル判定開始", __LINE__);
   
   bool buySignal = false;
   for(i = 0; i < MRA_FUTURE_STEP; i++) {
      // 高値と安値の予測値が逆転する可能性がある。
      // そのため、より高値予測値になったときの損益（High - last)と安値予測値になったときの損益を計算する。
      // 結果、どちらかの損失が損切値を超えていれば、ロング発注を控える。
      //     両方の利益が利確値を超えていれば、ロング発注をする。
      diff_Next_High_Point = futureData_High[i] - lastData;
      diff_Next_Low_Point  = futureData_Low[i]  - lastData;
      diff_Next_High_Point = nextData_High - lastData;
      diff_Next_Low_Point  = nextData_Low  - lastData;

      //
      // 買い判定に使う損失（損失の小さいほう）を計算する。
      //
      if(diff_Next_High_Point < 0.0 && diff_Next_Low_Point < 0.0) {  // 両方とも損失であれば、損失の小さいほうを買わない判定用変数diff_Point_Lossに入れる
         if(diff_Next_High_Point < diff_Next_Low_Point) {
            diff_Point_Loss = diff_Next_Low_Point;
         }
         else {
           diff_Point_Loss = diff_Next_High_Point;
         }
      }
      else if(diff_Next_High_Point < 0.0 && diff_Next_Low_Point >= 0.0) {  // 片方損失であれば、損失あるほうを買わない判定用変数diff_Point_Lossに入れる
        diff_Point_Loss = diff_Next_High_Point;
      }
      else if(diff_Next_High_Point > 0.0 && diff_Next_Low_Point < 0.0) {  // 片方損失であれば、損失があるほうを買わない判定用変数diff_Point_Lossに入れる
        diff_Point_Loss = diff_Next_Low_Point;
      }

      // 損失の小さいほうが、SL_PIPSを超えていれば、買いシグナルの判定終了
      if(diff_Point_Loss < 0.0 && change_Point2PIPS(local_symbol, MathAbs(diff_Point_Loss)) >= MRA_SL_PIPS) {
         buySignal = false;
         break;         
      }
      //
      // 買い判定に使う利益（利益の低い方）を計算して、diff_Point_Profitに入れる。
      //
      if(diff_Next_High_Point > 0.0 && diff_Next_Low_Point > 0.0) {  // 両方とも利益であれば、利益の小さい方を買う判定用変数diff_Point_Profitに入れる
         if(diff_Next_High_Point < diff_Next_Low_Point) {
            diff_Point_Profit = diff_Next_High_Point;
         }
         else {
           diff_Point_Profit = diff_Next_Low_Point;
         }
      }
      else if(diff_Next_High_Point < 0.0 && diff_Next_Low_Point >= 0.0) {  // 片方利益であれば、利益のあるほうを買う判定用変数diff_Point_Profitに入れる
        diff_Point_Profit = diff_Next_Low_Point;
      }
      else if(diff_Next_High_Point >= 0.0 && diff_Next_Low_Point < 0.0) {  // 片方損失であれば、損失あるほうを買う判定用変数diff_Point_Profitに入れる
        diff_Point_Profit = diff_Next_High_Point;
      }
     
      if(diff_Point_Profit >= 0.0 && change_Point2PIPS(local_symbol, MathAbs(diff_Point_Profit)) >= MRA_TP_PIPS) {
         buySignal = true;
         break;
      }
      
   }
//printf("[%d]MRA.mqh 時間計測用--買いシグナル判定終了", __LINE__);

//printf("[%d]MRA.mqh 時間計測用--売りシグナル判定開始", __LINE__);
   bool sellSignal = false;
   for(i = 0; i < MRA_FUTURE_STEP; i++) {
      // 高値と安値の予測値が逆転する可能性がある。
      // そのため、より高値予測値になったときの損益（last - High)と安値予測値になったときの損益を計算する。
      // 結果、どちらかの損失が損切値を超えていれば、ロング発注を控える。
      //     両方の利益が利確値を超えていれば、ロング発注をする。
      diff_Next_High_Point = lastData - futureData_High[i];
      diff_Next_Low_Point  = lastData - futureData_Low[i];
      //
      // 売り判定に使う損失（損失の小さいほう）を計算する。
      //
      if(diff_Next_High_Point < 0.0 && diff_Next_Low_Point < 0.0) {  // 両方とも損失であれば、損失の小さいほうを売らない判定用変数diff_Point_Lossに入れる
         if(diff_Next_High_Point < diff_Next_Low_Point) {
            diff_Point_Loss = diff_Next_Low_Point;
         }
         else {
           diff_Point_Loss = diff_Next_High_Point;
         }
      }
      else if(diff_Next_High_Point < 0.0 && diff_Next_Low_Point >= 0.0) {  // 片方損失であれば、損失あるほうを買わない判定用変数diff_Point_Lossに入れる
        diff_Point_Loss = diff_Next_High_Point;
      }
      else if(diff_Next_High_Point > 0.0 && diff_Next_Low_Point < 0.0) {  // 片方損失であれば、損失があるほうを買わない判定用変数diff_Point_Lossに入れる
        diff_Point_Loss = diff_Next_Low_Point;
      }

      // 損失の小さいほうが、SL_PIPSを超えていれば、買いシグナルの判定終了
      if(diff_Point_Loss < 0.0 && change_Point2PIPS(local_symbol, MathAbs(diff_Point_Loss)) >= MRA_SL_PIPS) {
         sellSignal = false;
         break;         
      }
      //
      // 買い判定に使う利益（利益の低い方）を計算して、diff_Point_Profitに入れる。
      //
      if(diff_Next_High_Point > 0.0 && diff_Next_Low_Point > 0.0) {  // 両方とも利益であれば、利益の小さい方を買う判定用変数diff_Point_Profitに入れる
         if(diff_Next_High_Point < diff_Next_Low_Point) {
            diff_Point_Profit = diff_Next_High_Point;
         }
         else {
           diff_Point_Profit = diff_Next_Low_Point;
         }
      }
      else if(diff_Next_High_Point < 0.0 && diff_Next_Low_Point >= 0.0) {  // 片方利益であれば、利益のあるほうを買う判定用変数diff_Point_Profitに入れる
        diff_Point_Profit = diff_Next_Low_Point;
      }
      else if(diff_Next_High_Point >= 0.0 && diff_Next_Low_Point < 0.0) {  // 片方損失であれば、損失あるほうを買う判定用変数diff_Point_Profitに入れる
        diff_Point_Profit = diff_Next_High_Point;
      }
     
      if(diff_Point_Profit >= 0.0 && change_Point2PIPS(local_symbol, MathAbs(diff_Point_Profit)) >= MRA_TP_PIPS) {
         sellSignal = true;
         break;
      }
      
   }
//printf("[%d]MRA.mqh 時間計測用--売りシグナル判定終了", __LINE__);

if(buySignal == true && sellSignal == true) {
//printf("[%d]MRA.mqh 時間計測用--売り、買い共にtrue", __LINE__);
}
else if(buySignal == true && sellSignal != true) {
//printf("[%d]MRA.mqh 時間計測用--買のみtrue", __LINE__);
}
else if(buySignal != true && sellSignal == true) {
//printf("[%d]MRA.mqh 時間計測用--売りのみtrue", __LINE__);
}
else if(buySignal != true && sellSignal != true) {
//printf("[%d]MRA.mqh 時間計測用--売り、解ともにfalse", __LINE__);
}

   int retBuySellSignal = NO_SIGNAL;
   int trend = get_Trend_EMA_PERIODH4(timeframe, 0);
   if(buySignal == true && trend == UpTrend) {
      retBuySellSignal = BUY_SIGNAL;
   }
   else if(sellSignal == true && trend == DownTrend) {
      retBuySellSignal = SELL_SIGNAL;
   }
   else {
      retBuySellSignal = NO_SIGNAL;
   }   


   return retBuySellSignal;

}

*/

