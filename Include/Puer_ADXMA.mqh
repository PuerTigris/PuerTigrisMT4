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
int ADXMA_LONGMAMODE  = 2;  // SMA200を計算する際に使用。ENUM_MA_METHODの値である0,1,2,3のいずれか。デフォルト値は0(MODE_SMA)。
int ADXMA_SHORTMAMODE = 3;  // EMA10を計算する際に使用。 ENUM_MA_METHODの値である0,1,2,3のいずれか。デフォルト値は1(MODE_EMA)。
   // ENUM_MA_METHOD
   // ID        値   詳細
   // MODE_SMA  0    単純移動平均
   // MODE_EMA  1    指数移動平均
   // MODE_SMMA 2    平滑移動平均
   // MODE_LWMA 3    加重移動平均
int ADXMA_SLOPESPAN = 25;  // ADXの傾きを計算する際のシフト数。2以上100未満。
int ADXMA_LS_MIN_DISTANCE_PIPS = 16; // SMA200とEMA10の距離（絶対値）が、この値以上の時にのみ取引実行。単位はPIPS。
*/
//+------------------------------------------------------------------+
//|23.ADXMA                                                 　　　   |
//+------------------------------------------------------------------+
/*
https://xn--fx-xt3c.jp/adx-ma-scal/
・SMA200：長期トレンド（価格との位置関係で売買方向を決める）
・EMA10 ：短期トレンド（ADXと併せてトリガーとなる）
・ADX　 ：トレンドの勢い（40以上75以下で上昇中を狙う）
・15分足を使う。

▼買いのルール
・価格がSMA200より上
・価格がEMA10の帯を上抜け。帯は、EMA10（High, Low, Close）で形成される。
・ADXが40以上で上昇中
この条件が揃ったらエントリー。
タイミングによってはEMA10の束を抜けた時にADXが40以下だったり、40以上でも下落していたりするケースもあります。
そんな時には慌てず条件が再び揃うのを待ちましょう。

売りの場合は単純に（SMAとEMAのみ）反対に考えてOK。ADXは買いと同じ。
▼売りのルール
・価格がSMA200より下
・価格がEMA10の帯を下抜け。帯は、EMA10（High, Low, Close）で形成される。
・ADXが40以上で上昇中（これは、買いと同じ）


勝率を上げる工夫
勝率を上げるためには、EMA10とSMA200の位置関係が明確な場所を選ぶのが鉄則。
・EMA10とSMA200が明確に離れている場所を狙う。
・EMA10とSMA200が絡み合う場所は見送る。
*/

int entryADXMA() {
   int mSignal = NO_SIGNAL;

   if(ADXMA_LONGMAMODE < 0 || ADXMA_LONGMAMODE > 3) {
      mSignal = NO_SIGNAL;
      return mSignal;
   }
   if(ADXMA_SHORTMAMODE < 0 || ADXMA_SHORTMAMODE > 3) {
      mSignal = NO_SIGNAL;
      return mSignal;
   }
   // SMA200の計算
   double sma200 = iMA(
                       global_Symbol,         // 通貨ペア
                       0,                     // 時間軸
                       200,                   // MAの平均期間
                       0,                     // MAシフト
                       ADXMA_LONGMAMODE,      // MAの平均化メソッド
                       PRICE_CLOSE,           // 適用価格
                       1                      // シフト
                       );
   if(sma200 <= 0.0) {
      mSignal = NO_SIGNAL;
      return mSignal;
   }

   int mTrend = 0;
   // ▼買いのルール
   // ・価格がSMA200より上
   // ・価格がEMA10の帯を上抜け。帯は、EMA10（High, Low, Close）で形成される。
   // ・ADXが40以上で上昇中
   double close1 = Close[1];
   double ema10_High = 0.0;
   double ema10_Low = 0.0;
   double ema10_Close = 0.0;
   //
   // ・価格がSMA200より上
   //
   // 計算時間短縮のため、EMA10（High, Low, Close）を別のif文とした。
   if(NormalizeDouble(close1, global_Digits) >= NormalizeDouble(sma200, global_Digits) ) {
      //
      // ・価格がEMA10の帯を上抜け。
      //   20220624 ema10_Low < ema10_Close < ema10_Highと想定されるので、Close1が上抜けたかどうかをLow, Close, Highの順に変更した。
      //

      //
      // EMA10（Low)の計算
      ema10_Low  = iMA(
                       global_Symbol,         // 通貨ペア
                       0,                     // 時間軸
                       10,                    // MAの平均期間
                       0,                     // MAシフト
                       ADXMA_SHORTMAMODE,     // MAの平均化メソッド
                       PRICE_LOW,             // 適用価格
                       1                      // シフト
                       );
      if(ema10_Low  <= 0.0) {
         mSignal = NO_SIGNAL;
         return mSignal;
      }
      // 価格が、EMA10（Low)を上抜けていなければ、NO_SIGNALを返す。
      if(NormalizeDouble(close1, global_Digits) <= NormalizeDouble(ema10_Low, global_Digits)) {
         mSignal = NO_SIGNAL;
         return mSignal;
      }
      //
      // EMA10（Close)の計算
      ema10_Close  = iMA(
                         global_Symbol,         // 通貨ペア
                         0,                     // 時間軸
                         10,                    // MAの平均期間
                         0,                     // MAシフト
                         ADXMA_SHORTMAMODE,     // MAの平均化メソッド
                         PRICE_CLOSE,           // 適用価格
                         1                      // シフト
                         );
      if(ema10_Close  <= 0.0) {
         mSignal = NO_SIGNAL;
         return mSignal;
      }
      // 価格が、EMA10（Close)を上抜けていなければ、NO_SIGNALを返す。
      if(NormalizeDouble(close1, global_Digits) <= NormalizeDouble(ema10_Close, global_Digits)) {
         mSignal = NO_SIGNAL;
         return mSignal;
      }

      // EMA10（High)の計算
      ema10_High = iMA(
                       global_Symbol,         // 通貨ペア
                       0,                     // 時間軸
                       10,                    // MAの平均期間
                       0,                     // MAシフト
                       ADXMA_SHORTMAMODE,     // MAの平均化メソッド
                       PRICE_HIGH,            // 適用価格
                       1                      // シフト
                       );
      if(ema10_High <= 0.0) {
         mSignal = NO_SIGNAL;
         return mSignal;
      }
      // 価格が、EMA10（High)を上抜けていなければ、NO_SIGNALを返す。
      if(NormalizeDouble(close1, global_Digits) <= NormalizeDouble(ema10_High, global_Digits)) {
         mSignal = NO_SIGNAL;
         return mSignal;
      }
      // ここまでの処理で、"価格がEMA10の帯を上抜け。"を確認済み。
      
      // ・ADXが40以上で上昇中
      // ADXの傾きを計算する。 
      mTrend = getADXTrend(ADXMA_SLOPESPAN);
      if(mTrend == UpTrend) {
         mSignal = BUY_SIGNAL;
      }      
   } 
   //
   // ・価格がSMA200より下
   //
   else if(NormalizeDouble(close1, global_Digits) < NormalizeDouble(sma200, global_Digits) ) {
      //
      // ・価格がEMA10の帯を下抜け。
      //   20220624 ema10_Low < ema10_Close < ema10_Highと想定されるので、Close1が下抜けたかどうかをHigh、Close、Lowの順に変更した。
      //
      //

      // EMA10（High)の計算
      ema10_High = iMA(
                       global_Symbol,         // 通貨ペア
                       0,                     // 時間軸
                       10,                    // MAの平均期間
                       0,                     // MAシフト
                       ADXMA_SHORTMAMODE,     // MAの平均化メソッド
                       PRICE_HIGH,            // 適用価格
                       1                      // シフト
                       );
      if(ema10_High <= 0.0) {
         mSignal = NO_SIGNAL;
         return mSignal;
      }
      // 価格が、EMA10（High)を下抜けていなければ、NO_SIGNALを返す。
      if(NormalizeDouble(close1, global_Digits) >= NormalizeDouble(ema10_High, global_Digits)) {
         mSignal = NO_SIGNAL;
         return mSignal;
      }
      //
      // EMA10（Close)の計算
      ema10_Close  = iMA(
                         global_Symbol,         // 通貨ペア
                         0,                     // 時間軸
                         10,                    // MAの平均期間
                         0,                     // MAシフト
                         ADXMA_SHORTMAMODE,     // MAの平均化メソッド
                         PRICE_CLOSE,           // 適用価格
                         1                      // シフト
                       );
      if(ema10_Close  <= 0.0) {
         mSignal = NO_SIGNAL;
         return mSignal;
      }
      // 価格が、EMA10（Close)を下抜けていなければ、NO_SIGNALを返す。
      if(NormalizeDouble(close1, global_Digits) >= NormalizeDouble(ema10_Close, global_Digits)) {
         mSignal = NO_SIGNAL;
         return mSignal;
      }

      // EMA10（Low)の計算
      ema10_Low  = iMA(
                       global_Symbol,         // 通貨ペア
                       0,                     // 時間軸
                       10,                    // MAの平均期間
                       0,                     // MAシフト
                       ADXMA_SHORTMAMODE,     // MAの平均化メソッド
                       PRICE_LOW,             // 適用価格
                       1                      // シフト
                       );
      if(ema10_Low  <= 0.0) {
         mSignal = NO_SIGNAL;
         return mSignal;
      }
      // 価格が、EMA10（Low)を下抜けていなければ、NO_SIGNALを返す。
      if(NormalizeDouble(close1, global_Digits) >= NormalizeDouble(ema10_Low, global_Digits)) {
         mSignal = NO_SIGNAL;
         return mSignal;
      }

      // ここまでの処理で、"価格がEMA10の帯を下抜け。"を確認済み。
      
      // ・ADXが40以上で上昇中
      // ADXの傾きを計算する。 
      mTrend = getADXTrend(ADXMA_SLOPESPAN);
      if(mTrend == UpTrend) {
         mSignal = SELL_SIGNAL;
      }
   } 


   // 返り値候補mSignalが、BUY_SIGNALかSELL_SIGNALの場合は、
   // SMA200とema10の直近3シフトの最短距離を調べる。
   // その最短距離が、ADXMA_LS_MIN_DISTANCE_PIPS未満の時は、
   // 返り値候補mSignalをNO_SIGNALにする。
   double mDistance = 0.0;
   if(mSignal == BUY_SIGNAL || mSignal == SELL_SIGNAL) {
      mDistance = getMinDistance();
      if(NormalizeDouble(mDistance, global_Digits) < NormalizeDouble(ADXMA_LS_MIN_DISTANCE_PIPS, global_Digits)) {
string buf = "";
if(mSignal == BUY_SIGNAL) {
   buf = "買いシグナル";
}
if(mSignal == SELL_SIGNAL) {
   buf = "売りシグナル";
}
//printf("[%d]ADXMA　SMA200とEMA10の最短距離が%s PIPS　< 設定値%s PIPSのため、%s取消", __LINE__, DoubleToStr(mDistance), buf);
         mSignal = NO_SIGNAL;
      }
   }
   


   return mSignal;
}	


// 直近3シフトのSMA200とEMA10の最短距離（絶対値）を返す。
// ただし、途中でSMA200とEMA10が交差している場合は、0を返す。
double getMinDistance(){
   double mDistance = DOUBLE_VALUE_MAX;
   int i;
   bool flagCross = false; // SMA200とEMA10が交差したらtrue。
   int mLargerMA = 0; // SMA200が大きければ、1。EMA10が大きければ-1
   for(i = 1; i < 4; i++) {
      double sma200 = iMA(
                          global_Symbol,         // 通貨ペア
                          0,                     // 時間軸
                          200,                   // MAの平均期間
                          0,                     // MAシフト
                          ADXMA_LONGMAMODE,      // MAの平均化メソッド
                          PRICE_CLOSE,           // 適用価格
                          i                      // シフト
                          );
      if(sma200  <= 0.0) {
         mDistance = 0.0;
         return mDistance;
      }

      // EMA10（Close)の計算
      double ema10_Close  = iMA(
                             global_Symbol,         // 通貨ペア
                             0,                     // 時間軸
                             10,                    // MAの平均期間
                             0,                     // MAシフト
                             ADXMA_SHORTMAMODE,     // MAの平均化メソッド
                             PRICE_CLOSE,           // 適用価格
                             i                      // シフト
                             );
      if(ema10_Close  <= 0.0) {
         mDistance = 0.0;
         return mDistance;
      }

      double mDistanceBuf = (NormalizeDouble(sma200, global_Digits) - NormalizeDouble(ema10_Close, global_Digits)) / global_Points;
      if(mDistance > 0.0) {
         // mLargerMAが未設定の場合は、+1を設定する。
         if(mLargerMA == 0) {
            mLargerMA = 1;
         }
         // mLargerMAが-1の場合は、SMA200とEMA10が交差しているので、flagCrossをtrueにする。
         else if(mLargerMA == -1) {
            flagCross = true;
         }
      }
      else if(mDistance < 0.0) {
         // mLargerMAが未設定の場合は、-1を設定する。
         if(mLargerMA == 0) {
            mLargerMA = -1;
         }
         // mLargerMAが+1の場合は、SMA200とEMA10が交差しているので、flagCrossをtrueにする。
         else if(mLargerMA == 1) {
            flagCross = true;
         }
      }
      
      // 距離の絶対値が、mDistanceより小さければ、その距離をmDistanceに代入する。 
      if(NormalizeDouble(MathAbs(mDistanceBuf), global_Digits) < NormalizeDouble(mDistance, global_Digits)) {
         mDistance = NormalizeDouble(MathAbs(mDistanceBuf), global_Digits);
      }
   }

   // SMA200とEMA10が交差しているか、mDistanceが初期値のままであれば、距離を0.0とする。
   if(flagCross == true 
      || NormalizeDouble(mDistance, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MAX, global_Digits) ) {
      mDistance = 0.0;
   }

   return mDistance;
}

// ADXの値で、トレンドを計算する。
// 引数trendSpanは、ADXの傾きを計算する際のシフト数。2以上100以下。
// UpTrend   :40以上75以下で上昇中。引数trendSpan個のADXの回帰直線の傾きが正。
// DownTrend :40以上75以下で下落中。引数trendSpan個のADXの回帰直線の傾きが負。
// NoTrend   :上記以外
int getADXTrend(int trendSpan) {
   if(trendSpan < 2 || trendSpan > 100) {
      return NoTrend;
   }

   int i = 0;
   double mADX[101]; // ADX[0]はシフト1のADXの値。ADX[100]は使用しない。
   // mADX[]の初期化
   for(i = 0; i < 100; i++) {
      mADX[i] = 0.0;
   }

   // シフト1のADXが40以上75以下の時のみ、トレンド発生とみなす。
   mADX[0] = iADX(global_Symbol,0,14,0,0,1); 
   if(mADX[0] < 40.0 || mADX[0] > 75.0) {
      return NoTrend;
   }

   for(i = 1; i < trendSpan; i++) {
      mADX[i] = iADX(global_Symbol,0,14,0,0,i+1);  // mADX[1]はシフト2のADXであり、
                                                   // mADX[i]は、シフト(i+1)のADXであることに注意。
      if(mADX[i] < 40.0 || mADX[i] > 75.0) {
      return NoTrend;
   }
   }

   double mSlope = 0.0;    // 関数calcRegressionLineで計算する傾きが入る。
   double mIntercept = 0.0;// 関数calcRegressionLineで計算する切片が入る。ただし、今回は切片は使用しない。

/*
   for(i = 1; i < trendSpan; i++) {
      printf("[%d]ADXMA　mADX[%d] = %s", __LINE__, i, DoubleToStr(mADX[i]));  
   }
*/
   bool flag = calcRegressionLine(mADX, trendSpan, mSlope, mIntercept);
   // 傾きと切片の計算失敗時は、トレンド無しとする。
   if(flag == false 
      || mSlope <= DOUBLE_VALUE_MIN  
      || mIntercept <= DOUBLE_VALUE_MIN) {
      return NoTrend;
   }

   // mADX[0]が直近(シフト=1)、mADX[trendSpan - 1]が最古(シフト=trendSpan)のため、
   // 関数calcRegressionLineで計算した結果は、トレンドが発生している場合は逆になる。
   if(mSlope > 0.0) {
      return DownTrend;
   }
   else if(mSlope < 0.0 && mSlope > DOUBLE_VALUE_MIN) {
      return UpTrend;
   }
   else {
      return NoTrend;
   }

   return NoTrend;
}


