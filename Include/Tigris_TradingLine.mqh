#include <Tigris_GLOBALS.mqh>
#include <Tigris_COMMON.mqh>
//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
// トレーディングライン
double   g_past_max     = DOUBLE_VALUE_MIN; // 過去の最高値
datetime g_past_maxTime = -1;               // 過去の最高値の時間
double   g_past_min     = DOUBLE_VALUE_MIN; // 過去の最安値
datetime g_past_minTime = -1;               // 過去の最安値の時間
double   g_past_width   = DOUBLE_VALUE_MIN; // 過去値幅。past_max - past_min
double   g_long_Min     = DOUBLE_VALUE_MIN; // ロング取引を許可する最小値
double   g_long_Max     = DOUBLE_VALUE_MIN; // ロング取引を許可する最大値
double   g_short_Min    = DOUBLE_VALUE_MIN; // ショート取引を許可する最小値
double   g_short_Max    = DOUBLE_VALUE_MIN; // ショート取引を許可する最大値



//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	

extern string TRADABLELINESTitle="---取引可能な領域の計算---";
int    TIME_FRAME_MAXMIN     = 7;     // 1～9最高値、最安値の参照期間の単位。
int    SHIFT_SIZE_MAXMIN     = 90;   // 最高値、最安値の参照期間
double ENTRY_WIDTH_PIPS      = 0.05;  // エントリーする間隔。PIPS数。
input  double ENTRY_WIDTH_PER = 10.0; // ロング、ショート共に最高値と最安値から何パーセントを取引不可とするか。
//
// 20250112　SHORT_ENTRY_WIDTH_PER, LONG_ENTRY_WIDTH_PERはあまり使わないため、外部パラーメータからグローバル変数に変更した。
//
double SHORT_ENTRY_WIDTH_PER = 50.0; // ショート実施帯域。過去最高値から何パーセント下までショートするか
double LONG_ENTRY_WIDTH_PER  = 50.0; // ロング実施帯域。過去最安値から何パーセント上までロングするか

// extern double ALLOWABLE_DIFF_PER    = 0.0;   // 使わない場合は、0。価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値とみなすか。 （約定間隔ENTRY_WIDTH_PIPS20pips*許容誤差ALLOWABLE_DIFF_PER10%なら差が2PIPSまでは同じ約定値）




//+------------------------------------------------------------------+
//|   取引の可否を意味する境界を計算する。                           |
//|   計算結果をグローバル変数にコピーする。                         |
//+------------------------------------------------------------------+
bool update_TradingLines(
   string   mSymbol,      // 計算対象の通貨ペア
   ENUM_TIMEFRAMES      mTimeframe,   // 計算に用いる時間軸
   int      mShiftSise    // 何シフト前までさかのぼって、最大、最小を求めるか。 = SHIFT_SIZE_MAXMIN;
   ) {
   double   past_max;     // 過去の最高値
   datetime past_maxTime; // 過去の最高値の時間
   double   past_min;     // 過去の最安値
   datetime past_minTime; // 過去の最安値の時間
   double   past_width;   // 過去値幅。past_max - past_min
   double   Long_Min;     // ロング取引を許可する最小値
   double   Long_Max;     // ロング取引を許可する最大値
   double   Short_Min;    // ショート取引を許可する最小値
   double   Short_Max;    // ショート取引を許可する最大値
                    
   bool mflag_calc_TradingLines = false;
   mflag_calc_TradingLines = 
      calc_TradingLines(mSymbol,      // 通貨ペア
                        mTimeframe,   // 計算に使う時間軸
                        mShiftSise,   // 計算対象にするシフト数
                        past_max,     // 出力：過去の最高値
                        past_maxTime, // 出力：過去の最高値の時間
                        past_min,     // 出力：過去の最安値
                        past_minTime, // 出力：過去の最安値の時間
                        past_width,   // 出力：過去値幅。past_max - past_min
                        Long_Min,     // 出力：ロング取引を許可する最小値
                        Long_Max,     // 出力：ロング取引を許可する最大値
                        Short_Min,    // 出力：ショート取引を許可する最小値
                        Short_Max     // 出力：ショート取引を許可する最大値                       
                       );
   if(mflag_calc_TradingLines == false) {
      return false;
   }   
   else {
      // グローバル変数に値をコピーする。
      g_past_max     = past_max;
      g_past_maxTime = past_maxTime;
      g_past_min     = past_min;
      g_past_minTime = past_minTime;
      g_past_width   = past_width;
      g_long_Min     = Long_Min;
      g_long_Max     = Long_Max;
      g_short_Min    = Short_Min;
      g_short_Max    = Short_Max;      
   }
   return true;
}


//+------------------------------------------------------------------+
//|   取引の可否を意味する境界を計算する。  計算開始位置をシフト0以外にするときは、別関数を使う|
//+------------------------------------------------------------------+
// 旧名称get_TradingLines
// 計算に使う時間軸とシフト数をグローバル変数とするバージョン
bool calc_TradingLines(string   mSymbol,         // 通貨ペア
                       double   &mPast_max,     // 出力：過去の最高値
                       datetime &mPast_maxTime, // 出力：過去の最高値の時間
                       double   &mPast_min,     // 出力：過去の最安値
                       datetime &mPast_minTime, // 出力：過去の最安値の時間
                       double   &mPast_width,   // 出力：過去値幅。past_max - past_min
                       double   &mLong_Min,     // 出力：ロング取引を許可する最小値
                       double   &mLong_Max,     // 出力：ロング取引を許可する最大値
                       double   &mShort_Min,    // 出力：ショート取引を許可する最小値
                       double   &mShort_Max     // 出力：ショート取引を許可する最大値
                       ) {
   int mIndex = 0;
printf( "[%d]TRADINGLINE symbol=>%s<  時間軸=%d  シフトサイズ=%d"  , __LINE__, mSymbol, TIME_FRAME_MAXMIN, SHIFT_SIZE_MAXMIN);

   mIndex = iHighest(    // 指定した通貨ペア・時間軸の最高値インデックスを取得
             mSymbol,    // 通貨ペア
             TIME_FRAME_MAXMIN, // 時間軸 
             MODE_HIGH,  // データタイプ[高値を指定]
             SHIFT_SIZE_MAXMIN, // 検索カウント。時間軸TIME_FRAME1TO9をSHIFT_SIZE個参照する。
             0           // 開始インデックス。高値更新を繰り返した場合を考えて、0番目のバーも計算に含める
   );
                  

   if(mIndex >= 0) {
      mPast_max = iHigh(         // 指定した通貨ペア・時間軸の高値を取得
                     mSymbol,    // 通貨ペア
                     TIME_FRAME_MAXMIN, // 時間軸 
                     mIndex      // インデックス[iHighestで取得したインデックスを指定]
      );
      mPast_maxTime = iTime(mSymbol, TIME_FRAME_MAXMIN, mIndex);
   }
   else {
      return false;
   }

   mIndex = 0;
   mIndex = iLowest(             // 指定した通貨ペア・時間軸の最高値インデックスを取得
                    mSymbol,     // 通貨ペア
                    TIME_FRAME_MAXMIN,  // 時間軸 
                    MODE_LOW,    // データタイプ[安値を指定]
                    SHIFT_SIZE_MAXMIN,  // 検索カウント。時間軸TIME_FRAME1TO9をSHIFT_SIZE個参照する。
                    0            // 開始インデックス。安値更新を繰り返した場合を考えて、0番目のバーも計算に含める
   );


   if(mIndex >= 0) {
      mPast_min = iLow(            // 指定した通貨ペア・時間軸の高値を取得
                       mSymbol,    // 通貨ペア
                       TIME_FRAME_MAXMIN, // 時間軸 
                       mIndex      // インデックス[iHighestで取得したインデックスを指定]
                     );
      mPast_minTime = iTime(mSymbol, TIME_FRAME_MAXMIN, mIndex);
   }
   else {     
      return false;
   }   

   if(mPast_min <= 0.0 && mPast_max <= 0.0) {

   
      return false;   
   }

   if(NormalizeDouble(mPast_min, global_Digits) > NormalizeDouble(mPast_max, global_Digits)) {
      return false;   
   }

   //過去値幅past_widthを、最高値past_max - 最安値past_minとする。
   mPast_width = NormalizeDouble(mPast_max - mPast_min, global_Digits);

//
//ロング取引及びショート取引を許可する価格帯をグローバル変数に設定する。 
//気配値が、上限または下限に近いときは、新規取引はしない
//past_width = past_max - past_min
//mShort_Max----------------------------------------------------- past_max
//             → SHORT_ENTRY_WIDTH_PER (ショート実行不可能)          ↓
//mShort_Min-----------------------------------------------------   ↓
//　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　↓
//　　　　　　　　　　　取引可能　　　　　　　　　　　　　　　　　mPast_width
//                　　　　　　　　　　　　　　　　　　　　　　　　  ↑
//mLong_Max -----------------------------------------------------   ↑
//             → LONG_ENTRY_WIDTH_PER (ロング実行不可能)             ↑
//mLomg_Min------------------------------------------------------ past_min


   mShort_Max = mPast_max - mPast_width * ENTRY_WIDTH_PER / 100.0; 
   mShort_Min = mPast_min + mPast_width * ENTRY_WIDTH_PER / 100.0; 
   mLong_Max = mShort_Max;
   mLong_Min = mShort_Min;
   
   return true;
}



bool calc_TradingLines(string  mSymbol,        // 通貨ペア
                       ENUM_TIMEFRAMES  mTimeframe,     // 計算に使う時間軸
                       int      mShiftSize,     // 計算対象にするシフト数。何シフト前までさかのぼって、最大、最小を求めるか。
                       double   &mPast_max,     // 出力：過去の最高値
                       datetime &mPast_maxTime, // 出力：過去の最高値の時間
                       double   &mPast_min,     // 出力：過去の最安値
                       datetime &mPast_minTime, // 出力：過去の最安値の時間
                       double   &mPast_width,   // 出力：過去値幅。past_max - past_min
                       double   &mLong_Min,     // 出力：ロング取引を許可する最小値
                       double   &mLong_Max,     // 出力：ロング取引を許可する最大値
                       double   &mShort_Min,    // 出力：ショート取引を許可する最小値
                       double   &mShort_Max     // 出力：ショート取引を許可する最大値
                       ) {
   int mIndex = 0;
//printf( "[%d]TRADINGLINE symbol=>%s<  時間軸=%d  シフトサイズ=%d"  , __LINE__, mSymbol, mTimeframe, mShiftSize);

   mIndex = iHighest(    // 指定した通貨ペア・時間軸の最高値インデックスを取得
             mSymbol,    // 通貨ペア
             mTimeframe, // 時間軸 
             MODE_HIGH,  // データタイプ[高値を指定]
             mShiftSize, // 検索カウント。時間軸TIME_FRAME1TO9をSHIFT_SIZE個参照する。
             0           // 開始インデックス。高値更新を繰り返した場合を考えて、0番目のバーも計算に含める
   );
                  

   if(mIndex >= 0) {
      mPast_max = iHigh(         // 指定した通貨ペア・時間軸の高値を取得
                     mSymbol,    // 通貨ペア
                     mTimeframe, // 時間軸 
                     mIndex      // インデックス[iHighestで取得したインデックスを指定]
      );
      mPast_maxTime = iTime(mSymbol, mTimeframe, mIndex);
   }
   else {

      return false;
   }

   mIndex = 0;
   mIndex = iLowest(             // 指定した通貨ペア・時間軸の最高値インデックスを取得
                    mSymbol,     // 通貨ペア
                    mTimeframe,  // 時間軸 
                    MODE_LOW,    // データタイプ[安値を指定]
                    mShiftSize,  // 検索カウント。時間軸TIME_FRAME1TO9をSHIFT_SIZE個参照する。
                    0            // 開始インデックス。安値更新を繰り返した場合を考えて、0番目のバーも計算に含める
   );


   if(mIndex >= 0) {
      mPast_min = iLow(            // 指定した通貨ペア・時間軸の高値を取得
                       mSymbol,    // 通貨ペア
                       mTimeframe, // 時間軸 
                       mIndex      // インデックス[iHighestで取得したインデックスを指定]
                     );
      mPast_minTime = iTime(mSymbol, mTimeframe, mIndex);
   }
   else {                
      return false;
   }   

   if(mPast_min <= 0.0 && mPast_max <= 0.0) {
      return false;   
   }

   if(NormalizeDouble(mPast_min, global_Digits) > NormalizeDouble(mPast_max, global_Digits)) {
      return false;   
   }

   //過去値幅past_widthを、最高値past_max - 最安値past_minとする。
   mPast_width = NormalizeDouble(mPast_max - mPast_min, global_Digits);

//
//
//ロング取引及びショート取引を許可する価格帯をグローバル変数に設定する。 
//気配値が、上限または下限に近いときは、新規取引はしない
//past_width = past_max - past_min
//mShort_Max----------------------------------------------------- past_max
//             → SHORT_ENTRY_WIDTH_PER (ショート実行不可能)          ↓
//mShort_Min-----------------------------------------------------   ↓
//　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　↓
//　　　　　　　　　　　取引可能　　　　　　　　　　　　　　　　　mPast_width
//                　　　　　　　　　　　　　　　　　　　　　　　　  ↑
//mLong_Max -----------------------------------------------------   ↑
//             → LONG_ENTRY_WIDTH_PER (ロング実行不可能)             ↑
//mLomg_Min------------------------------------------------------ past_min


   mShort_Max = mPast_max - mPast_width * ENTRY_WIDTH_PER / 100.0; 
   mShort_Min = mPast_min + mPast_width * ENTRY_WIDTH_PER / 100.0;  
   mLong_Max = mShort_Max;
   mLong_Min = mShort_Min;
   
   return true;
}


bool calc_TradingLines(string  mSymbol,         // 通貨ペア
                       int      mTimeframe,     // 計算に使う時間軸
                       int      mStartShift,    // 計算対象とする先頭のシフト番号。
                       int      mShiftSize,     // 計算対象にするシフト数。何シフト前までさかのぼって、最大、最小を求めるか。
                       double   &mPast_max,     // 出力：過去の最高値
                       datetime &mPast_maxTime, // 出力：過去の最高値の時間
                       double   &mPast_min,     // 出力：過去の最安値
                       datetime &mPast_minTime, // 出力：過去の最安値の時間
                       double   &mPast_width,   // 出力：過去値幅。past_max - past_min
                       double   &mLong_Min,     // 出力：ロング取引を許可する最小値
                       double   &mLong_Max,     // 出力：ロング取引を許可する最大値
                       double   &mShort_Min,    // 出力：ショート取引を許可する最小値
                       double   &mShort_Max     // 出力：ショート取引を許可する最大値
                       ) {
   int mIndex = 0;

   mIndex = iHighest(    // 指定した通貨ペア・時間軸の最高値インデックスを取得
             mSymbol,    // 通貨ペア
             mTimeframe, // 時間軸 
             MODE_HIGH,  // データタイプ[高値を指定]
             mShiftSize, // 検索カウント。時間軸TIME_FRAME1TO9をSHIFT_SIZE個参照する。
             0 + mStartShift // 開始インデックス。高値更新を繰り返した場合を考えて、0番目のバーも計算に含める
   );
      
   if(mIndex >= 0) {
      mPast_max = iHigh(         // 指定した通貨ペア・時間軸の高値を取得
                     mSymbol,    // 通貨ペア
                     mTimeframe, // 時間軸 
                     mIndex      // インデックス[iHighestで取得したインデックスを指定]
      );
      mPast_maxTime = iTime(mSymbol, mTimeframe, mIndex);
   }
   else {
      return false;
   }
   
   mIndex = 0;
   mIndex = iLowest(             // 指定した通貨ペア・時間軸の最高値インデックスを取得
                    mSymbol,     // 通貨ペア
                    mTimeframe,  // 時間軸 
                    MODE_LOW,    // データタイプ[安値を指定]
                    mShiftSize,  // 検索カウント。時間軸TIME_FRAME1TO9をSHIFT_SIZE個参照する。
                    0 + mStartShift // 開始インデックス。安値更新を繰り返した場合を考えて、0番目のバーも計算に含める
   );

   
   if(mIndex >= 0) {
      mPast_min = iLow(            // 指定した通貨ペア・時間軸の高値を取得
                       mSymbol,    // 通貨ペア
                       mTimeframe, // 時間軸 
                       mIndex      // インデックス[iHighestで取得したインデックスを指定]
                     );
      mPast_minTime = iTime(mSymbol, mTimeframe, mIndex);
   }
   else {                
      return false;
   }   

   if(mPast_min <= 0.0 && mPast_max <= 0.0) {
      return false;   
   }

   if(NormalizeDouble(mPast_min, global_Digits) > NormalizeDouble(mPast_max, global_Digits)) {
      return false;   
   }

   //過去値幅past_widthを、最高値past_max - 最安値past_minとする。
   mPast_width = NormalizeDouble(mPast_max - mPast_min, global_Digits);

//
//
//ロング取引及びショート取引を許可する価格帯をグローバル変数に設定する。 
//気配値が、上限または下限に近いときは、新規取引はしない
//past_width = past_max - past_min
//mShort_Max----------------------------------------------------- past_max
//             → SHORT_ENTRY_WIDTH_PER (ショート実行不可能)          ↓
//mShort_Min-----------------------------------------------------   ↓
//　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　↓
//　　　　　　　　　　　取引可能　　　　　　　　　　　　　　　　　mPast_width
//                　　　　　　　　　　　　　　　　　　　　　　　　  ↑
//mLong_Max -----------------------------------------------------   ↑
//             → LONG_ENTRY_WIDTH_PER (ロング実行不可能)             ↑
//mLomg_Min------------------------------------------------------ past_min

   mShort_Max = mPast_max - mPast_width * ENTRY_WIDTH_PER / 100.0; 
   mShort_Min = mPast_min + mPast_width * LONG_ENTRY_WIDTH_PER / 100.0;  
   mLong_Max = mShort_Max;
   mLong_Min = mShort_Min;
   
   return true;
}


bool read_TradingLines(double   &mpast_max,     // 出力：過去の最高値
                       datetime &mpast_maxTime, // 出力：過去の最高値の時間
                       double   &mpast_min,     // 出力：過去の最安値
                       datetime &mpast_minTime, // 出力：過去の最安値の時間
                       double   &mpast_width,   // 出力：過去値幅。past_max - past_min
                       double   &mlong_Min,     // 出力：ロング取引を許可する最小値
                       double   &mlong_Max,     // 出力：ロング取引を許可する最大値
                       double   &mshort_Min,    // 出力：ショート取引を許可する最小値
                       double   &mshort_Max     // 出力：ショート取引を許可する最大値
                                            ) {
   mpast_max     = NormalizeDouble(g_past_max, global_Digits);
   if(mpast_max <= 0.0) {
printf( "[%d]TradingLineエラー mpast_maxの取得失敗" , __LINE__ );
      return false;
   }

   mpast_maxTime = g_past_maxTime;
   if(mpast_maxTime <= 0) {
printf( "[%d]TradingLineエラー mpast_maxTimeの取得失敗" , __LINE__ );
      return false;
   }

   mpast_min     = NormalizeDouble(g_past_min, global_Digits);
   if(mpast_min <= 0.0) {
printf( "[%d]TradingLineエラー mpast_minの取得失敗:：%s" , __LINE__ );
      return false;
   }

   mpast_minTime = g_past_minTime;
   if(mpast_minTime <= 0) {
printf( "[%d]TradingLineエラー mpast_minTimeの取得失敗:：%s" , __LINE__ );
      return false;
   }

   mpast_width   = NormalizeDouble(g_past_width, global_Digits);   
   if(mpast_width <= 0.0) {
printf( "[%d]TradingLineエラー mpast_widthの取得失敗:：%s" , __LINE__ );
      return false;
   }

   mlong_Min     = NormalizeDouble(g_long_Min, global_Digits);
   if(mlong_Min <= 0.0) {
printf( "[%d]TradingLineエラー mlong_Minの取得失敗:：%s" , __LINE__ );
      return false;
   }

   mlong_Max     = NormalizeDouble(g_long_Max, global_Digits);
   if(mlong_Max <= 0.0) {
printf( "[%d]TradingLineエラー mlong_Maxの取得失敗:：%s" , __LINE__ );
      return false;
   }

   mshort_Min    = NormalizeDouble(g_short_Min, global_Digits);
   if(mshort_Min <= 0.0) {
printf( "[%d]TradingLineエラー mshort_Minの取得失敗:：%s" , __LINE__ );
      return false;
   }

   mshort_Max    = NormalizeDouble(g_short_Max, global_Digits);
   if(mshort_Max <= 0.0) {
printf( "[%d]TradingLineエラー mshort_Maxの取得失敗:：%s" , __LINE__ );
      return false;
   }
   
   return true;
}



void updateExternalParam_TradingLine() {
/*
   //
   // TIME_FRAME_MAXMINの設定値が取りうる値かどうかをチェックの上、MQL4の定数に変換する。
   // 
   if(TIME_FRAME_MAXMIN < 0 || TIME_FRAME_MAXMIN > 9) {
      TIME_FRAME_MAXMIN = 0;
   }
   switch(TIME_FRAME_MAXMIN) {
      case 1:TIME_FRAME_MAXMIN = PERIOD_M1;
             break;
      case 2:TIME_FRAME_MAXMIN = PERIOD_M5;
             break;
      case 3:TIME_FRAME_MAXMIN = PERIOD_M15;
             break;
      case 4:TIME_FRAME_MAXMIN = PERIOD_M30;
             break;
      case 5:TIME_FRAME_MAXMIN = PERIOD_H1;
             break;
      case 6:TIME_FRAME_MAXMIN = PERIOD_H4;
             break;
      case 7:TIME_FRAME_MAXMIN = PERIOD_D1;
             break;
      case 8:TIME_FRAME_MAXMIN = PERIOD_W1;
             break;
      case 9:TIME_FRAME_MAXMIN = PERIOD_MN1;
             break;
      default:TIME_FRAME_MAXMIN = PERIOD_CURRENT;
   }   
*/
}

//　ロングとショート両方できない値なら、-1
// 一方だけ可能なら、0
// ロングとショート両方可能なら、＋１を返す。
int is_TradablePrice() {
   bool flag_read_TradingLines;
   double   past_max;     // 過去の最高値
   datetime past_maxTime; // 過去の最高値の時間
   double   past_min;     // 過去の最安値
   datetime past_minTime; // 過去の最安値の時間
   double   past_width;   // 過去値幅。past_max - past_min
   double   long_Min;     // ロング取引を許可する最小値
   double   long_Max;     // ロング取引を許可する最大値
   double   short_Min;    // ショート取引を許可する最小値
   double   short_Max;    // ショート取引を許可する最大値   
   ENUM_TIMEFRAMES TIME_FRAME_MAXMIN_ENUM = changeInt2ENUMTIMEFRAME(TIME_FRAME_MAXMIN);
   double mMarketinfoMODE_ASK;
   double mMarketinfoMODE_BID;
   flag_read_TradingLines = read_TradingLines(past_max,  // 出力：過去の最高値
                                              past_maxTime,   // 出力：過去の最高値の時間
                                              past_min,       // 出力：過去の最安値
                                              past_minTime,   // 出力：過去の最安値の時間
                                              past_width,     // 出力：過去値幅。past_max - past_min
                                              long_Min,       // 出力：ロング取引を許可する最小値
                                              long_Max,       // 出力：ロング取引を許可する最大値
                                              short_Min,      // 出力：ショート取引を許可する最小値
                                              short_Max       // 出力：ショート取引を許可する最大値
                                            );  

   bool flag_is_TradablePrice;
   bool longable = false;
   // ロングが可能かを検証する。
   mMarketinfoMODE_ASK = MarketInfo(global_Symbol,MODE_ASK);   
   flag_is_TradablePrice = 
      is_TradablePrice(0,
                       BUY_SIGNAL,
                       long_Max,
                       long_Min,
                       ENTRY_WIDTH_PIPS,     // 何PIPSの間隔をあけるか
                       mMarketinfoMODE_ASK); // 発注予定値
   if(flag_is_TradablePrice == false) {
      longable = false;
   }
   else {
      longable = true;
   }

   bool shortable = false;
   // ショートが可能かを検証する。
   mMarketinfoMODE_BID = MarketInfo(global_Symbol,MODE_BID);
   flag_is_TradablePrice = 
      is_TradablePrice(0,
                       SELL_SIGNAL,
                       short_Max,
                       short_Min,
                       ENTRY_WIDTH_PIPS,     // 何PIPSの間隔をあけるか
                       mMarketinfoMODE_BID); // 発注予定値
   if(flag_is_TradablePrice == false) {
      shortable = false;
   }
   else {
      shortable = true;
   }
 
   if(longable == true && shortable == true) {
      return 1;
   }
   else if(longable == false && shortable == false) {
      return -1;
   }
   else {
      return 0;
   }
   
}