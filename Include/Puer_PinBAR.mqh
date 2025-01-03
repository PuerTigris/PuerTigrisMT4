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

//EAが同じ足で描画するのを避けるための変数。
static datetime drawTime  = 0;
static int      arrow_cnt = 0;

//EAが同じ足で同じ計算をするのを避けるための変数
static datetime prevCalcTime = 0;

//最後に髭が見つかった時間を保存する。同じ髭でくりかえし、計算するのを避けるため。
datetime lastChallengeUp = 0;  // 下髭 
datetime lastChallengeDown = 0;  // 上髭

// No3用の条件を満たす最新の値。
int PinBarNo3_Signal = INT_VALUE_MIN;
double PinBarNo3_Price = DOUBLE_VALUE_MIN;
datetime PinBarNo3_Time = 0;
//+------------------------------------------------------------------+
//|97.PinBAR                                                 　　　   |
//+------------------------------------------------------------------+
int entryPinBar() {
//printf( "[%d]PB 確認entryPinBar()が使われている" , __LINE__);

   int mSignal  = entryPinBar_Shift(1);
   return mSignal;
}

int org2entryPinBar() {
printf( "[%d]PB 確認entryPinBar()が使われている" , __LINE__);

   int mSignal  = NO_SIGNAL;
   // PinBarMethod
   // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5
   // 110(6)=No3とNo5, 111=No1とNo3とNo5  
   if(PinBarMethod == 1) {            // 001(1)=No1
      mSignal = entryPinBar_No1(1);
      return mSignal;
   }
   else if(PinBarMethod == 2) {       // 010(2)=No3
      mSignal = entryPinBar_No3(1);
      return mSignal;
   }
   else if(PinBarMethod == 3) {       // 011(3)=No1とNo3

      mSignal = entryPinBar_No1(1);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No3(1);
      return mSignal;
   }
   else if(PinBarMethod == 4) {       // 100(4)=No5
      mSignal = entryPinBar_No5(1);
      return mSignal;
   }
   else if(PinBarMethod == 5) {       // 101(5)=No1とNo5
      mSignal = entryPinBar_No1(1);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No5(1);
      return mSignal;
   }
   else if(PinBarMethod == 6) {       // 110(6)=No3とNo5
      mSignal = entryPinBar_No3(1);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No5(1);
      if(mSignal != NO_SIGNAL) {
      }       
      return mSignal;
   }
   else if(PinBarMethod == 7) {       // 111=No1とNo3とNo5
      mSignal = entryPinBar_No1(1);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No3(1);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No5(1);
      return mSignal;
   }
      
   return NO_SIGNAL;
}

int entryPinBar_Shift(int mShift) {
//printf( "[%d]PB ーーーーーーーーーーーーーーーー確認entryPinBar(mshift)が使われている" , __LINE__);

/*
printf( "[%d]PIN ピンや髭の計算に使っている変数 PinBarBODY_MIN_PER=%s PinBarPIN_MAX_PER=%s" , __LINE__, 
DoubleToStr(PinBarBODY_MIN_PER, global_Digits),
DoubleToStr(PinBarPIN_MAX_PER, global_Digits)
);
*/
   int mSignal  = NO_SIGNAL;
   // PinBarMethod
   // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5
   // 110(6)=No3とNo5, 111=No1とNo3とNo5  
   if(PinBarMethod == 1) {
      mSignal = entryPinBar_No1(mShift);
      return mSignal;
   }
   else if(PinBarMethod == 2) {
      mSignal = entryPinBar_No3(mShift);
      return mSignal;
   }
   else if(PinBarMethod == 3) {
      mSignal = entryPinBar_No1(mShift);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No3(mShift);
      return mSignal;
   }
   else if(PinBarMethod == 4) {
      mSignal = entryPinBar_No5(mShift);
      return mSignal;
   }
   else if(PinBarMethod == 5) {
      mSignal = entryPinBar_No1(mShift);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No5(mShift);
      return mSignal;
   }
   else if(PinBarMethod == 6) {
      mSignal = entryPinBar_No3(mShift);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No5(mShift);
      if(mSignal != NO_SIGNAL) {
      }      
      return mSignal;
   }
   else if(PinBarMethod == 7) {
      mSignal = entryPinBar_No1(mShift);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No3(mShift);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No5(mShift);
      return mSignal;
   }
      
   return NO_SIGNAL;
}





void init_PinBarNo3Params() {
   PinBarNo3_Signal = INT_VALUE_MIN;
   PinBarNo3_Price = DOUBLE_VALUE_MIN;
   PinBarNo3_Time = 0;
}






// ※シフト0の売買判断において使用する前提の関数。
// シフト2から直前数本前のシフトmPinBarBackstepまで検索して、大陽線または大陰線があれば、trueを返す。
// 実体が上ヒゲよりも長いローソク足を「大陽線」とする。上ヒゲが実体よりも長い場合は見送り。実体と上ヒゲがほとんど同じ長さだった場合も見送る。下ヒゲの長さは考慮しなくてよい。
// 実体が下ヒゲよりも長いローソク足を「大陽線」とする。下ヒゲが実体よりも長い場合は見送り。実体と下ヒゲがほとんど同じ長さだった場合も見送る。上ヒゲの長さは考慮しなくてよい。
// ただし、探しているの線とは逆の線が先に見つかった場合（陽線を探す時に、より近い時刻に陰線が見つかる）はFALSEを返す。
bool exist_BigBody(int    mTimeFrame,
                   int    mSignal,             // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                   int    mPinBarBackstep,     // 何本前のシフトまで、陽線又は、陰線を探すか。
                   double mPinBarBODY_MIN_PER) {// 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
   if(mPinBarBackstep < 2) {
      return false;
   } 
   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、falseとする。
   if(mTimeFrame < PERIOD_CURRENT || mTimeFrame > PERIOD_MN1) {
      return false;
   }

   if(mSignal != BUY_SIGNAL && mSignal != SELL_SIGNAL) {
      return false;
   }

   int i;
   bool flag_is_BigBody_BUYSIGNAL = false;  // 大陽線の時、true
   bool flag_is_BigBody_SELLSIGNAL = false;  // 大陰線の時、true

   for(i = 2; i < 2 + mPinBarBackstep; i++) {
      // 注目したシフトが大陽線かを調べる
//printf("[%d]PB exist_BigBodyでis_BigBody", __LINE__);
      
      flag_is_BigBody_BUYSIGNAL = is_BigBody(mTimeFrame,
                                             BUY_SIGNAL,         // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                                             i,                  // このシフトが、大陽線又は、大陰線を判断する。
                                             mPinBarBODY_MIN_PER // 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
                                             ); 
      //
      // 注目したシフトが大陽線の場合      
      //
      if(flag_is_BigBody_BUYSIGNAL == true) {
         // 引数mSignalが大陽線を探しているのであれば、trueを返す
         if(mSignal == BUY_SIGNAL) {
            return true;
         }
         // 引数mSignalが大陰線を探しているのであれば、falseを返す
         else if(mSignal == SELL_SIGNAL) {
            return false;
         }
      }
      else {   // 注目したシフトが大陽線ではなかったので、大陰線を調べる
         // 注目したシフトが大陽線かを調べる
//printf("[%d]PB exist_BigBodyでis_BigBody", __LINE__);
         
         flag_is_BigBody_SELLSIGNAL = is_BigBody(mTimeFrame,
                                                 SELL_SIGNAL,         // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                                                 i,                  // このシフトが、大陽線又は、大陰線を判断する。
                                                 mPinBarBODY_MIN_PER // 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
                                                 ); 
         //
         // 大陰線の場合      
         //
         if(flag_is_BigBody_SELLSIGNAL== true) {
            // 引数mSignalが大陰線を探しているのであれば、trueを返す
            if(mSignal == SELL_SIGNAL) {
               return true;
            }
            // 引数mSignalが大陽線を探しているのであれば、falseを返す
            else if(mSignal == BUY_SIGNAL) {
               return false;
            }
         }
      }
   }   

   // ループ内で、大陽線も大陰線も見つからなかったのでfalseを返す。
   return false;
}



// 指定したシフトmShiftが、大陽線または大陰線があれば、trueを返す。
// 実体が上ヒゲよりも長いローソク足を「大陽線」とする。上ヒゲが実体よりも長い場合は見送り。実体と上ヒゲがほとんど同じ長さだった場合も見送る。下ヒゲの長さは考慮しなくてよい。
// 実体が下ヒゲよりも長いローソク足を「大陽線」とする。下ヒゲが実体よりも長い場合は見送り。実体と下ヒゲがほとんど同じ長さだった場合も見送る。上ヒゲの長さは考慮しなくてよい。
// ただし、探しているの線とは逆の線が先に見つかった場合（陽線を探す時に、より近い時刻に陰線が見つかる）はFALSEを返す。
bool is_BigBody(int    mTimeFrame,
                int    mSignal,            // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                int    mShift,             // このシフトが、大陽線又は、大陰線を判断する。
                double mPinBarBODY_MIN_PER // 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
                ) {
   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、falseとする。
   if(mTimeFrame < PERIOD_CURRENT || mTimeFrame > PERIOD_MN1) {
      return false;
   }

   if(mSignal != BUY_SIGNAL && mSignal != SELL_SIGNAL) {
      return false;
   }

   double close_i = DOUBLE_VALUE_MIN;
   double open_i  = DOUBLE_VALUE_MIN;
   double high_i  = DOUBLE_VALUE_MIN;
   double low_i   = DOUBLE_VALUE_MIN;
   double high_close_i = DOUBLE_VALUE_MIN;  // 大陽線を判断する時の上髭
   double low_close_i  = DOUBLE_VALUE_MIN;  // 大陰線を判断する時の下髭
   double body_i  = DOUBLE_VALUE_MIN; // 実体部分

   close_i = NormalizeDouble(iClose(global_Symbol, mTimeFrame, mShift), global_Digits);    
   open_i  = NormalizeDouble(iOpen(global_Symbol, mTimeFrame, mShift), global_Digits);

   //
   // 大陽線の場合      
   //
   // 実体が上ヒゲよりも長いローソク足を「大陽線」とする。上ヒゲが実体よりも長い場合は見送り。実体と上ヒゲがほとんど同じ長さだった場合も見送る。下ヒゲの長さは考慮しなくてよい。 
   // 陽線であること
   if(close_i > open_i){
      high_i       = NormalizeDouble(iHigh(global_Symbol, mTimeFrame, mShift), global_Digits); 
      low_i        = NormalizeDouble(iLow(global_Symbol, mTimeFrame, mShift), global_Digits);
      high_close_i = high_i - close_i; // 上ヒゲの長さ
      body_i       = close_i - open_i;       // 実体の長さ
      // 実体部分が、高値安値のmPinBarBODY_MIN_PERパーセントより大きいこと
      if( body_i > NormalizeDouble((high_i - low_i) * mPinBarBODY_MIN_PER / 100.0, global_Digits) 
         // かつ、上ヒゲより実体の方が長いこと
         && high_close_i < body_i ) {
         // 陽線を探していたのであれば、trueを返す
         if(mSignal == BUY_SIGNAL) {
ObjectCreate(ChartID(), "UP_ARROW", OBJ_ARROW_UP, mShift, Time[mShift], Close[mShift]);
/*printf("[%d] 大陽線発見！！　シフト=%d 時刻>%s< 　全長=%s  実体=%s > 上ヒゲ=%s", __LINE__, mTimeFrame, TimeToStr(iTime(global_Symbol, mTimeFrame, mShift)),
          DoubleToString(high_i - low_i, global_Digits),  // 全長
          DoubleToString(body_i, global_Digits),          // 実体
          DoubleToString(high_close_i, global_Digits)     // 上ヒゲ
      );*/

            return true;
         }
         // 陰線を探していたのであれば、falseを返す
         else {
            return false;
         }
      }
      else {
            return false;      
      }
   }
   //
   // 大陰線の場合      
   // 実体が下ヒゲよりも長いローソク足を「大陰線」とする。下ヒゲが実体よりも長い場合は見送り。
   // 陰線であること
   else if(close_i < open_i){
      high_i      = NormalizeDouble(iHigh(global_Symbol, mTimeFrame, mShift), global_Digits); 
      low_i       = NormalizeDouble(iLow(global_Symbol, mTimeFrame, mShift), global_Digits);
      low_close_i = close_i - low_i;  // 下髭
      body_i      = open_i - close_i;      // 実体の長さ
      // 実体部分が、高値安値のmPinBarBODY_MIN_PERパーセントより大きいこと
      if( body_i > NormalizeDouble((high_i - low_i) * mPinBarBODY_MIN_PER / 100.0, global_Digits) 
         // かつ、下ヒゲより実体の方が長いこと
         && low_close_i < body_i ) {
         
         // 陰線を探していたのであれば、trueを返す
         if(mSignal == SELL_SIGNAL) {
ObjectCreate(ChartID(), "DOWN_ARROW", OBJ_ARROW_DOWN, mShift, Time[mShift], Close[mShift]);
/*printf("[%d]PB 大陰線発見！！　シフト=%d 時刻>%s< 　全長=%s  実体=%s > 下ヒゲ=%s", __LINE__, mShift, TimeToStr(iTime(global_Symbol, mTimeFrame, mShift)),
          DoubleToString(high_i - low_i, global_Digits),  // 全長
          DoubleToString(body_i, global_Digits),          // 実体
          DoubleToString(low_close_i, global_Digits)      // 下ヒゲ
      );*/
            return true;
         }
         // 陽線を探していたのであれば、falseを返す
         else {
            return false;
         }
      }
      else {
         return false;
      }
   }
   // 陽線でも陰線でもない場合
   else {
      return false;
   }

   return false;
}






//************************************************************************
//************************************************************************
//************************************************************************
//****************************シフト指定バージョン************************
//************************************************************************
//************************************************************************
int entryPinBarShift(int mShift) {
   int mSignal  = NO_SIGNAL;
   int mSignal2 = NO_SIGNAL;
   int mSignal3 = NO_SIGNAL;
   // PinBarMethod
   // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5
   // 110(6)=No3とNo5, 111=No1とNo3とNo5  
   if(PinBarMethod == 1) {
      mSignal = entryPinBar_No1(mShift);
      return mSignal;
   }
   else if(PinBarMethod == 2) {
      mSignal = entryPinBar_No3(mShift);
      return mSignal;
   }
   else if(PinBarMethod == 3) {
      mSignal = entryPinBar_No3(mShift);
      if(mSignal != NO_SIGNAL) {
         mSignal2 = entryPinBar_No1(mShift);
         if(mSignal2 != NO_SIGNAL && mSignal == mSignal2) {
            return mSignal;
         }
      }
      return NO_SIGNAL;
   }
   else if(PinBarMethod == 4) {
      mSignal = entryPinBar_No5(mShift);
      return mSignal;
   }
   else if(PinBarMethod == 5) {
      mSignal = entryPinBar_No1(mShift);
      if(mSignal != NO_SIGNAL) {
         mSignal2 = entryPinBar_No5(mShift);
         if(mSignal2 != NO_SIGNAL && mSignal == mSignal2) {
            return mSignal;
         }
      }
      return mSignal;
   }
   else if(PinBarMethod == 6) {
      mSignal = entryPinBar_No5(mShift);
      if(mSignal != NO_SIGNAL) {
         mSignal2 = entryPinBar_No3(mShift);
         if(mSignal2 != NO_SIGNAL && mSignal == mSignal2) {
            return mSignal;
         }
      }
      return NO_SIGNAL;      
   }
   else if(PinBarMethod == 7) {
      mSignal = entryPinBar_No5(mShift);
      if(mSignal != NO_SIGNAL) {
         mSignal2 = entryPinBar_No3(mShift);
         if(mSignal2 != NO_SIGNAL && mSignal == mSignal2) {
            mSignal3 = entryPinBar_No1(mShift);
            if(mSignal3 != NO_SIGNAL && mSignal3 == mSignal2) {
               return mSignal;
            }
         }
      }
      return NO_SIGNAL;      
   }
      
   return NO_SIGNAL;
}




// シフトmShiftにおいて、SMA20とSMA50で雲が発生しているかを判断する。
// ・水色雲：SMA50よりSMA20が上にある上昇サイン＝UpTrendを返す
// ・茶色雲：SMA50よりSMA20が下にある下落サイン＝DownTrendを返す
// ・上記以外はNoTrendを返す。
int get_TrendCloud(string mSymbol,    // 通貨ペア
                   int    mTimeFrame, // 時間軸
                   int    mShift,     // 雲の発生を判断するシフト
                   double &mSMA20,    // 出力：雲の発生に判断したSMA20
                   double &mSMA50     // 出力：雲の発生に判断したSMA50
                   ) {
   mSMA20 = iMA( global_Symbol,// 通貨ペア
                 mTimeFrame,   // 時間軸
                 20,           // MAの平均期間
                 0,            // MAシフト
                 MODE_SMA,     // MAの平均化メソッド
                 PRICE_CLOSE,  // 適用価格
                 mShift        // シフト
                 );
   mSMA20 = NormalizeDouble(mSMA20, global_Digits);
                        
   mSMA50 = iMA( global_Symbol,// 通貨ペア
                 mTimeFrame,    // 時間軸
                 50,            // MAの平均期間
                 0,             // MAシフト
                 MODE_SMA,      // MAの平均化メソッド
                 PRICE_CLOSE,   // 適用価格
                 mShift         // シフト
                 );
   mSMA50 = NormalizeDouble(mSMA50, global_Digits);
//printf( "[%d]PIN SMA20, SMA50取得時間 %s" , __LINE__, TimeToStr(iTime(global_Symbol, mTimeFrame, 1)));

   // ・水色雲：SMA50よりSMA20が上にある上昇サインUpTrend
   // ・茶色雲：SMA50よりSMA20が下にある下落サインDownTrend
   if(mSMA20 > mSMA50) {
      return UpTrend;   // ・水色雲：SMA50よりSMA20が上にある上昇サイン
   }
   else if(mSMA20 < mSMA50) {
      return DownTrend; // ・茶色雲：SMA50よりSMA20が下にある下落サイン
   }
   else {
      return NoTrend;
   }

   return NoTrend;
}



// シフトmShiftから探し始めて、直前数本前のシフトmPinBarBackstepまで検索して、大陽線または大陰線があれば、trueを返す。
// 実体が上ヒゲよりも長いローソク足を「大陽線」とする。上ヒゲが実体よりも長い場合は見送り。実体と上ヒゲがほとんど同じ長さだった場合も見送る。下ヒゲの長さは考慮しなくてよい。
// 実体が下ヒゲよりも長いローソク足を「大陽線」とする。下ヒゲが実体よりも長い場合は見送り。実体と下ヒゲがほとんど同じ長さだった場合も見送る。上ヒゲの長さは考慮しなくてよい。
// ただし、探しているの線とは逆の線が先に見つかった場合（陽線を探す時に、より近い時刻に陰線が見つかる）はFALSEを返す。
bool exist_BigBody(int    mTimeFrame,
                   int    mSignal,             // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                   int    mShift,              // 陽線、陰線を探し始めるシフト番号
                   int    mPinBarBackstep,     // 何本前のシフトまで、陽線又は、陰線を探すか。
                   double mPinBarBODY_MIN_PER) {// 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
   if(mPinBarBackstep <= 0) {
      return false;
   } 
   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、falseとする。
   if(mTimeFrame < PERIOD_CURRENT || mTimeFrame > PERIOD_MN1) {
      return false;
   }

   if(mSignal != BUY_SIGNAL && mSignal != SELL_SIGNAL) {
      return false;
   }

   int i;
   bool flag_is_BigBody_BUYSIGNAL = false;  // 大陽線の時、true
   bool flag_is_BigBody_SELLSIGNAL = false;  // 大陰線の時、true

   for(i = mShift; i < mShift + mPinBarBackstep; i++) {
      // 注目したシフトが大陽線かを調べる      
        
      flag_is_BigBody_BUYSIGNAL = is_BigBody(mTimeFrame,
                                             BUY_SIGNAL,         // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                                             i,                  // このシフトが、大陽線又は、大陰線を判断する。
                                             mPinBarBODY_MIN_PER // 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
                                             ); 
      //
      // 注目したシフトが大陽線の場合      
      //
      if(flag_is_BigBody_BUYSIGNAL == true) {
         // 引数mSignalが大陽線を探しているのであれば、trueを返す
         if(mSignal == BUY_SIGNAL) {
            return true;
         }
         // 引数mSignalが大陰線を探しているのであれば、falseを返す
         else if(mSignal == SELL_SIGNAL) {
            return false;
         }
      }
      else {   // 注目したシフトが大陽線ではなかったので、大陰線を調べる
         // 注目したシフトが大陽線かを調べる        
         
         flag_is_BigBody_SELLSIGNAL = is_BigBody(mTimeFrame,
                                                 SELL_SIGNAL,         // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                                                 i,                  // このシフトが、大陽線又は、大陰線を判断する。
                                                 mPinBarBODY_MIN_PER // 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
                                                 ); 
         //
         // 大陰線の場合      
         //
         if(flag_is_BigBody_SELLSIGNAL== true) {
            // 引数mSignalが大陰線を探しているのであれば、trueを返す
            if(mSignal == SELL_SIGNAL) {
               return true;
            }
            // 引数mSignalが大陽線を探しているのであれば、falseを返す
            else if(mSignal == BUY_SIGNAL) {
               return false;
            }
         }
      }
   }   

   // ループ内で、大陽線も大陰線も見つからなかったのでfalseを返す。
   return false;
}




int entryPinBar_No1(int mShift) {

// No1：順張りピンバー手法
// 
// https://fx-works.jp/wp-content/uploads/2020/09/ebook.pdf
// 買いの場合
// １．1つ前のシフトが、SMA50、SMA20、SMA5 のパーフェクトオーダーを確認（下から SMA50、SMA20、SMA5 の順番に並ぶ）
// ２．1つ前のシフトのCloseが、SMA20、SMA5 の上でレートが推移している
// ３．2つ以上前の直近で「大陽線」の出現
// ４．1つ前で上向き矢印ピンバーの出現
// ５．次の足の始値で買いエントリー
// 
// 売りの場合
// １．1つ前のシフトが、SMA50、SMA20、SMA5 のパーフェクトオーダーを確認（上から SMA50、SMA20、SMA5 の順番に並ぶ）
// ２．1つ前のシフトのCloseが、SMA20、 SMA5 の下でレートが推移している
// ３．2つ以上前の直近で「大陰線」の出現
// ４．1つ前で下向き矢印ピンバーの出現
// ５．次の足の始値で売りエントリー

   int mSignal  = NO_SIGNAL;
   int mTimeFrame = getTimeFrame(PinBarTimeframe);
      
   datetime nowDT = iTime(global_Symbol, mTimeFrame, 0 + mShift);

   // 1つ前のシフトの移動平均を取得する。
   double SMA05 = iMA( global_Symbol,// 通貨ペア
                       mTimeFrame,   // 時間軸
                       5,   // MAの平均期間
                       0,            // MAシフト
                       MODE_SMA,     // MAの平均化メソッド
                       PRICE_CLOSE,  // 適用価格
                       1 + mShift    // シフト
                      );
   double SMA20 = iMA( global_Symbol,// 通貨ペア
                       mTimeFrame,   // 時間軸
                       20,   // MAの平均期間
                       0,            // MAシフト
                       MODE_SMA,     // MAの平均化メソッド
                       PRICE_CLOSE,  // 適用価格
                       1 + mShift    // シフト
                      );
   double SMA50 = iMA( global_Symbol,// 通貨ペア
                       mTimeFrame,   // 時間軸
                       50,   // MAの平均期間
                       0,            // MAシフト
                       MODE_SMA,     // MAの平均化メソッド
                       PRICE_CLOSE,  // 適用価格
                       1 + mShift    // シフト
                      );
   double close_1 = iClose(global_Symbol, mTimeFrame, 1 + mShift);         
   bool flag_exist_BigBody = false;
   bool flag_is_PinBar     = false;     
   bool flag_Trend         = NoTrend; // 1つ上の足のトレンドを計算した結果。    
   int  upper_TF           = get_UpperLowerPeriod_ENUM_TIMEFRAMES(mTimeFrame, 1); // 1つ上の時間軸


/*
if(NormalizeDouble(SMA05, global_Digits) >= NormalizeDouble(SMA20, global_Digits) 
   &&  
   NormalizeDouble(SMA20, global_Digits) >= NormalizeDouble(SMA50, global_Digits) ){
      printf( "[%d]PB entryPinBar_No1シグナル準備　SMA05>%s<　SMA20>%s<　SMA50>%s<　" , __LINE__, 
      DoubleToStr(SMA05, global_Digits),
      DoubleToStr(SMA20, global_Digits),
      DoubleToStr(SMA50, global_Digits)
   );
}
*/

   // 買いの場合（1つ上の時間軸が下落でないこと）
   // １．1つ前のシフトが、SMA50、SMA20、SMA5 のパーフェクトオーダーを確認（下から SMA50、SMA20、SMA5 の順番に並ぶ）
   // ２．1つ前のシフトのCloseが、SMA20、SMA5 の上でレートが推移している
   // ３．2つ以上前の直近で「大陽線」の出現。実体が上ヒゲよりも長いローソク足を「大陽線」とする。上ヒゲが実体よりも長い場合は見送り。実体と上ヒゲがほとんど同じ長さだった場合も見送る。下ヒゲの長さは考慮しなくてよい。
   // ４．1つ前のシフトで、上向き矢印ピンバーの出現
   // ５．次の足の始値で買いエントリー   
   
   if(NormalizeDouble(SMA05, global_Digits) >= NormalizeDouble(SMA20, global_Digits) 
      &&  
      NormalizeDouble(SMA20, global_Digits) >= NormalizeDouble(SMA50, global_Digits) 
      && 
      NormalizeDouble(SMA50, global_Digits) > 0.0) {
      if(NormalizeDouble(close_1, global_Digits) > NormalizeDouble(SMA20 , global_Digits)
         &&
         NormalizeDouble(close_1, global_Digits) > NormalizeDouble(SMA05 , global_Digits) ) {

         flag_exist_BigBody = 
            // シフト2かそれより前の直近が大陽線であればtrue
            exist_BigBody(mTimeFrame,         // 計算用時間軸
                          BUY_SIGNAL,         // 大陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                          2 + mShift,         // mShiftから2つ前のシフトから陽線を探す。
                          PinBarBackstep,     // mShiftから2つ前のシフトから何本前のシフトまで、陽線又は、陰線を探すか。
                          PinBarBODY_MIN_PER);// 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
         // シフト2以前の直近が大陽線で、シフト1が上向き矢印ピンバーを形成していたら、現時点で買いシグナルを出す。
         if(flag_exist_BigBody == true) {
            flag_is_PinBar = 
               is_PinBar(mTimeFrame,         // 計算用時間軸
                         BUY_SIGNAL,         // 陽線のPinBARを探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                         1 + mShift,         // mShiftから1つ前のシフトがPinBarを形成しているか
                         PinBarPIN_MAX_PER); // 実体部分(始値と終値の差）が最高値と最安値の何％以下ならPinBARとみなすか

            flag_Trend = get_Trend_EMA_PERIODH4(upper_TF, mShift);
            // シフト１が上向き矢印ピンバーを形成し、1つ上の足が下降トレンドでなければ買いシグナルを出す。
            if(flag_is_PinBar == true && flag_Trend == UpTrend) {

            
               return BUY_SIGNAL;
            }
         }
      }
   }

    
   // 売りの場合（1つ上の時間軸が上昇でないこと）
   // １．1つ前のシフトが、SMA50、SMA20、SMA5 のパーフェクトオーダーを確認（上から SMA50、SMA20、SMA5 の順番に並ぶ）
   // ２．1つ前のシフトのCloseが、SMA20、 SMA5 の下でレートが推移している
   // ３．2つ以上前の直近で「大陰線」の出現。実体が下ヒゲよりも長いローソク足を「大陽線」とする。下ヒゲが実体よりも長い場合は見送り。実体と下ヒゲがほとんど同じ長さだった場合も見送る。上ヒゲの長さは考慮しなくてよい。
   // ４．1つ前のシフトで、下向き矢印ピンバーの出現
   // ５．次の足の始値で売りエントリー
     
   if(NormalizeDouble(SMA05, global_Digits) <= NormalizeDouble(SMA20, global_Digits) 
      &&  
      NormalizeDouble(SMA20, global_Digits) <= NormalizeDouble(SMA50, global_Digits) 
      && 
      NormalizeDouble(SMA05, global_Digits) > 0.0) {
      if(NormalizeDouble(close_1, global_Digits) < NormalizeDouble(SMA20 , global_Digits)
         &&
         NormalizeDouble(close_1, global_Digits) < NormalizeDouble(SMA05 , global_Digits) ) {
         
         flag_exist_BigBody = 
            // シフト2かそれより前の直近が大陰線であればtrue
            exist_BigBody(mTimeFrame,         // 計算用時間軸
                          SELL_SIGNAL,        // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                          2 + mShift,         // mShiftから2つ前のシフトから陽線を探す。
                          PinBarBackstep,     // mShiftから2つ前のシフトから何本前のシフトまで、陽線又は、陰線を探すか。
                          PinBarBODY_MIN_PER);// 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
         // シフト2以前の直近が大陰線で、シフト1が下向き矢印ピンバーを形成していたら、現時点で売りシグナルを出す。    
         if(flag_exist_BigBody == true) {
            flag_is_PinBar = 
               is_PinBar(mTimeFrame,         // 計算用時間軸
                         SELL_SIGNAL,        // 陽線のPinBARを探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                         1 + mShift,         // mShiftから1つ前のシフトがPinBarを形成しているか
                         PinBarPIN_MAX_PER); // 実体部分(始値と終値の差）が最高値と最安値の何％以下ならPinBARとみなすか
                        
            flag_Trend = get_Trend_EMA_PERIODH4(upper_TF, mShift);
            // シフト１が下向き矢印ピンバーを形成し、1つ上の足が上昇トレンドでなければ買いシグナルを出す。             
            if(flag_is_PinBar == true && flag_Trend == DownTrend) {

               return SELL_SIGNAL;
            }
         }
      }
   }

   return NO_SIGNAL;
}	


//
// No3の再作成
//
// No3元ネタ
// 1. SMA5が水色雲(SMA20 > SMA50)のなかに潜る、あるいは下抜け
// 2. 上向き矢印ピンバー（下髭）が、水色雲の中、あるいは下で出現
// 3. 上向き矢印ピンバーの高値を上抜ける大陽線の出現(1本限定）
// 4. 上向き矢印ピンバーの高値に指値買い注文
int entryPinBar_No3(int mShift) {
   // シフトmShift+1からシフトmShift+100までの間で以下満たすシフトを探す
   int i;
   int  buySellSignal    = NO_SIGNAL;
   int  buyCandShift     = -1; // 買いシグナルが発生したシフト番号
   int  sellCandShift    = -1; // 売りシグナルが発生したシフト番号

   double SMA05 = 0.0;
   double SMA20 = 0.0;
   double SMA50 = 0.0;
   
   bool flag_is_BigBody;
   int  timeFrame = Period();
   // 
   // 買いシグナル
   // 
   for(i = mShift + 1; i <= mShift+100; i++ ) {
      // SMA5が水色雲の中に無ければ、終了
      SMA05 = iMA( global_Symbol,     // 通貨ペア
                   timeFrame,  // 時間軸
                   5,           // MAの平均期間
                   0,           // MAシフト
                   MODE_SMA,    // MAの平均化メソッド
                   PRICE_CLOSE, // 適用価格
                   i            // シフト
                  );
      SMA20 = iMA( global_Symbol,     // 通貨ペア
                   timeFrame,  // 時間軸
                   20,           // MAの平均期間
                   0,           // MAシフト
                   MODE_SMA,    // MAの平均化メソッド
                   PRICE_CLOSE, // 適用価格
                   i            // シフト
                  );
      SMA50 = iMA( global_Symbol,     // 通貨ペア
                   timeFrame,  // 時間軸
                   50,           // MAの平均期間
                   0,           // MAシフト
                   MODE_SMA,    // MAの平均化メソッド
                   PRICE_CLOSE, // 適用価格
                   i            // シフト
               );
      if(SMA20 > SMA50 // 水色雲
         && (SMA50 <= SMA05 && SMA05 <= SMA20) // SMA05が水色雲の中
      ) {
         // シフトiが大陽線の時
         flag_is_BigBody = is_BigBody(Period(), BUY_SIGNAL, i, PinBarBODY_MIN_PER);
         if(flag_is_BigBody == true) {
            // シフトiのClose（大陽線の実体上側）が、直前であるシフト(i+1)の高値以上の時
            if(iClose(global_Symbol, timeFrame,i) >= iHigh(global_Symbol, timeFrame,i+1) ){
               // シフト(i+1)が上向きピンバー（＝下髭）であれば、買いシグナル発生して終了
               bool flag_is_PinBar = is_PinBar(timeFrame, 
                                               BUY_SIGNAL, 
                                               i + 1, 
                                               PinBarPIN_MAX_PER);
               if(flag_is_PinBar == true) {
                  buyCandShift  = i;
               }
            }
         }
      }
      else {
         // SMA5が水色雲の中に無いので、終了
         break; 
      }
   }

   // 
   // 売りシグナル
   // 
   for(i = mShift + 1; i <= mShift+100; i++ ) {
      // SMA5が茶色雲の中に無ければ、終了
      SMA05 = iMA( global_Symbol,     // 通貨ペア
                   timeFrame,  // 時間軸
                   5,           // MAの平均期間
                   0,           // MAシフト
                   MODE_SMA,    // MAの平均化メソッド
                   PRICE_CLOSE, // 適用価格
                   i            // シフト
                  );
      SMA20 = iMA( global_Symbol,     // 通貨ペア
                   timeFrame,  // 時間軸
                   20,           // MAの平均期間
                   0,           // MAシフト
                   MODE_SMA,    // MAの平均化メソッド
                   PRICE_CLOSE, // 適用価格
                   i            // シフト
                  );
      SMA50 = iMA( global_Symbol,     // 通貨ペア
                   timeFrame,  // 時間軸
                   50,           // MAの平均期間
                   0,           // MAシフト
                   MODE_SMA,    // MAの平均化メソッド
                   PRICE_CLOSE, // 適用価格
                   i            // シフト
               );
      if(SMA20 < SMA50 // 茶色雲
         && (SMA50 >= SMA05 && SMA05 >= SMA20) // SMA05が茶色雲の中
      ) {
         // シフトiが大陰線の時
         flag_is_BigBody = is_BigBody(timeFrame, SELL_SIGNAL, i, PinBarBODY_MIN_PER);
         if(flag_is_BigBody == true) {
            // シフトiのClose（大陰線の実体下側）が、直前であるシフト(i+1)の安値以下の時
            if(iClose(global_Symbol, timeFrame,i) <= iLow(global_Symbol, timeFrame,i+1) ){
               // シフト(i+1)が下向きピンバー（＝上髭）であれば、売りシグナル発生して終了
               flag_is_PinBar = is_PinBar(timeFrame, 
                                               SELL_SIGNAL, 
                                               i + 1, 
                                               PinBarPIN_MAX_PER);
               if(flag_is_PinBar == true) {
                  sellCandShift  = i;
               }
            }
         }
      }
      else {
         // SMA5が茶色雲の中に無いので、終了
         break; 
      }
   }

   if(sellCandShift > buyCandShift) {
      if(buyCandShift >= 0) {
         buySellSignal = BUY_SIGNAL;
      }
      else if(sellCandShift >= 0) {
         buySellSignal = SELL_SIGNAL;
      }
   }
   else if(sellCandShift < buyCandShift) {
      if(sellCandShift >= 0) {
         buySellSignal = SELL_SIGNAL;
      }
      else if(buyCandShift >= 0) {
         buySellSignal = BUY_SIGNAL;
      }
   }

   return buySellSignal;
}

// No3元ネタ
// 1. SMA5が水色雲のなかに潜る、あるいは下抜け
// 2. 上向き矢印ピンバー（下髭）が、水色雲の中、あるいは下で出現
// 3. 上向き矢印ピンバーの高値を上抜ける大陽線の出現(1本限定）
// 4. 上向き矢印ピンバーの高値に指値買い注文
int orgentryPinBar_No3(int mShift) {
   int mTimeFrame = getTimeFrame(PinBarTimeframe);
   int upper_TF = get_UpperLowerPeriod_ENUM_TIMEFRAMES(mTimeFrame, 1); // 1つ上の時間軸
   int mSignal  = NO_SIGNAL;
   int trendCloud = NoTrend;
   double SMA05 = DOUBLE_VALUE_MIN;
   double SMA20 = DOUBLE_VALUE_MIN;
   double SMA50 = DOUBLE_VALUE_MIN;  
   int ret = NO_SIGNAL;
   datetime dtNow = iTime(global_Symbol, mTimeFrame, mShift);  // 本来はTimeLocal();だが、mShiftシフト手前の時間を取得できないため、iTime関数で代理
   

// 1．PinBarNo3_Timeが現時点より前で、0より大きければ、現在のASK/BIDを使ってシグナルを判断
//   初期値は、ret = NO_SIGNAL
// 　PinBarSignal = 1の時、現時点も水色雲かつASKがPinBarNo3_Price以下の時、BUY_SIGNALを返す準備　→　ret = BUY_SIGNAL
// 　PinBarSignal = 2の時、ASKがPinBarNo3_Price以下の時、BUY_SIGNALを返す準備　→　ret = BUY_SIGNAL
// 　PinBarSignal = 3の時、現時点も茶色雲かつBIDがPinBarNo3_Price以上の時、SELL_SIGNALを返す　→　ret = SELL_SIGNAL
// 　PinBarSignal = 4の時、ASKがPinBarNo3_Price以上の時、SELL_SIGNALを返す　→　ret = SELL_SIGNAL
//  retが、NO_SIGNAL以外の時、PinBarNo3_Signal, PinBarNo3_Price, PinBarNo3_Timeを初期化して、retを返す。
//  retが、NO_SIGNALの時は、現時点から2つ前にピンバーが発生し、かつ、1つ前が大陽線または大陰線かを検証。

   int trendCloud_Shift0;
   int flag_Trend;
   
   // 
   // 現シフト０を出発点として、直近で、2つ前にピンバー、1つ前に大陽線・大陰線が発生していることを探す。
   //
   int i;
   bool flag_get_PinBarNo3_Firststep = false;
   for(i = 0; i < 100; i++) {
      flag_get_PinBarNo3_Firststep = 
      get_PinBarNo3_Firststep(mTimeFrame,
                              mShift + i,       // 計算を始めるシフト番号。このシフトの2つ前でピンバーが発生し、1つ前で大陽線・大陰線が発生していれば、true
                              PinBarNo3_Signal, // 出力：条件を満たした場合の雲の色、ピンバーの形、直後の線の値から、1～４を返す
                              PinBarNo3_Price,  // 出力：下髭の高値、または、上髭の安値 
                              PinBarNo3_Time);  // 出力：条件を達成した時間。引数mStartShiftの時間   
      if(flag_get_PinBarNo3_Firststep == true) {
         break;
      }
   }
   // 上記の探索期間中に条件を満たすピンバーと足が見つからなければ、NO_SIGNAL
   if(flag_get_PinBarNo3_Firststep == false 
      || (flag_get_PinBarNo3_Firststep == true && (PinBarNo3_Signal < 1 || PinBarNo3_Signal > 4))
       ) {
      return NO_SIGNAL;
   }
   else {
   }

   if(PinBarNo3_Time > 0 && PinBarNo3_Time <= dtNow) {  // 売買シグナルを出すためのピンバーと大陰線・陽線の組あわせが発生済み。
      if(PinBarNo3_Signal == 1) { 
         trendCloud_Shift0 =  get_TrendCloud(global_Symbol,    // 通貨ペア
                                   mTimeFrame, // 時間軸
                                   0 + mShift,     // 雲の発生を判断するシフト
                                   SMA20,    // 出力：雲の発生に判断したSMA20
                                   SMA50     // 出力：雲の発生に判断したSMA50
                                  );

         flag_Trend = get_Trend_EMA_PERIODH4(upper_TF, mShift);
         if( trendCloud_Shift0 != DownTrend  // 下降トレンドの茶雲以外ならOK
            && flag_Trend == UpTrend       // １つ上が上昇トレンドであればOK
            && NormalizeDouble(iLow(global_Symbol, mTimeFrame, mShift) , global_Digits) <= NormalizeDouble(PinBarNo3_Price, global_Digits)) {  // 本来はAskだが、シフトmShift時点のAskは取得できないため、当時の最安値が下髭の高値を割り込んだかどうかを判断する。
               init_PinBarNo3Params();
printf("[%d]PB entryPinBar_No3でロングシグナル>%s<", __LINE__,TimeToStr(iTime(global_Symbol, upper_TF, mShift)));

               return BUY_SIGNAL;
         }
      }
      else if(PinBarNo3_Signal == 2) { 
         flag_Trend = get_Trend_EMA_PERIODH4(upper_TF, mShift);
         if(flag_Trend == UpTrend 
            && NormalizeDouble(iLow(global_Symbol, mTimeFrame, mShift) , global_Digits) <= NormalizeDouble(PinBarNo3_Price, global_Digits)) {  // 本来はAskだが、シフトmShift時点のAskは取得できないため、当時の最安値が下髭の高値を割り込んだかどうかを判断する。
            init_PinBarNo3Params();
printf("[%d]PB entryPinBar_No3でロングシグナル>%s<", __LINE__,TimeToStr(iTime(global_Symbol, upper_TF, mShift)));

            
            return BUY_SIGNAL;
         }
      }
      else if(PinBarNo3_Signal == 3) { 
         trendCloud_Shift0 =  get_TrendCloud(global_Symbol,    // 通貨ペア
                                   mTimeFrame, // 時間軸
                                   0 + mShift,     // 雲の発生を判断するシフト
                                   SMA20,    // 出力：雲の発生に判断したSMA20
                                   SMA50     // 出力：雲の発生に判断したSMA50
                                  );
         flag_Trend = get_Trend_EMA_PERIODH4(upper_TF, mShift);
         if(trendCloud_Shift0 != UpTrend   // 上昇トレンドの水雲以外ならOK
            && flag_Trend == DownTrend     // １つ上が下降トレンドであればOK
            && NormalizeDouble(iHigh(global_Symbol, mTimeFrame, mShift), global_Digits) >= NormalizeDouble(PinBarNo3_Price, global_Digits)) {  // 本来はBidを使うが、シフトmShift時点のBidは取得できないため、当時の最高値が上髭の安値を上回ったかどうかを判断する。
               init_PinBarNo3Params();
printf("[%d]PB entryPinBar_No3でショートシグナル>%s<", __LINE__,TimeToStr(iTime(global_Symbol, upper_TF, mShift)));

               return SELL_SIGNAL;
         }
      }
      else if(PinBarNo3_Signal == 4) { 
         flag_Trend = get_Trend_EMA_PERIODH4(upper_TF, mShift);
         if(flag_Trend == DownTrend 
            && NormalizeDouble(iHigh(global_Symbol, mTimeFrame, mShift), global_Digits) >= NormalizeDouble(PinBarNo3_Price, global_Digits)) {  // 本来はBidを使うが、シフトmShift時点のBidは取得できないため、当時の最高値が上髭の安値を上回ったかどうかを判断する。
            init_PinBarNo3Params();
printf("[%d]PB entryPinBar_No3でショートシグナル>%s<", __LINE__,TimeToStr(iTime(global_Symbol, upper_TF, mShift)));

            
            return SELL_SIGNAL;
         }         
      }
   }
  
   return NO_SIGNAL;
}



//
// 売買判定をする計算対象シフトの１つ前から順に、直近で条件を満たしているシフトを探す。
// 関数に引数渡ししたシフト、2つ前のシフトでピンバーが発生し、引数のシフト1つ前で大陽線・大陰線が発生していれば、
// PinBarNo3_Signal, PinBarNo3_Price, PinBarNo3_Timeを更新する処理。
// ①2つ前のシフトで、SMA5が水色の中にもぐり、上向き矢印ピンバー。直後がピンの高値を超える大陽線  →　PinBarSignal = 1;
// ②2つ前のシフトで、SMA5が水色の下に突き抜けて、上向き矢印ピンバー。直後がピンの高値を超える大陽線  →　PinBarSignal = 2;
// ③2つ前のシフトで、SMA5が茶色の中にもぐり、下向き矢印ピンバー。直後がピンの安値を超える大陰線 →　PinBarSignal = 3;
// ④2つ前のシフトで、SMA5が茶色の上に突き抜けて、下向き矢印ピンバー。直後がピンの安値を超える大陰線  →　PinBarSignal = 4;
bool get_PinBarNo3_Firststep(int mTimeFrame,
                             int mStartShift,        // 計算を始めるシフト番号。このシフトの2つ前でピンバーが発生し、1つ前で大陽線・大陰線が発生していれば、true
                             int &mPinBarNo3_Signal, // 出力：条件を満たした場合の雲の色、ピンバーの形、直後の線の値から、1～４を返す
                             double &mPinBarNo3_Price,// 出力：下髭の高値、または、上髭の安値 
                             datetime &mPinBarNo3_Time // 出力：条件を達成した時間。引数mStartShiftの時間
   ) {
   
   // ２．都度、以下を調べる。初期値は、PinBarNo3_Signal = INT_VALUE_MIN;
   // 　①2つ前のシフトで、SMA5が水色の中にもぐり、上向き矢印ピンバー。直後がピンの高値を超える大陽線  →　PinBarSignal = 1;
   // 　②2つ前のシフトで、SMA5が水色の下に突き抜けて、上向き矢印ピンバー。直後がピンの高値を超える大陽線  →　PinBarSignal = 2;
   // 　③2つ前のシフトで、SMA5が茶色の中にもぐり、下向き矢印ピンバー。直後がピンの安値を超える大陰線 →　PinBarSignal = 3;
   // 　④2つ前のシフトで、SMA5が茶色の上に突き抜けて、下向き矢印ピンバー。直後がピンの安値を超える大陰線  →　PinBarSignal = 4;
   // シフトmStartShiftにおいて、SMA20とSMA50で雲が発生しているかを判断する。
   // ・水色雲：SMA50よりSMA20が上にある上昇サイン＝UpTrendを返す=SMA20 > mSMA50
   // ・茶色雲：SMA50よりSMA20が下にある下落サイン＝DownTrendを返す=SMA20 < mSMA50
   double SMA05 = DOUBLE_VALUE_MIN;
   double SMA20 = DOUBLE_VALUE_MIN;
   double SMA50 = DOUBLE_VALUE_MIN; 
   int trendCloud = NoTrend;
      
   mPinBarNo3_Signal = INT_VALUE_MIN;
   mPinBarNo3_Price  = DOUBLE_VALUE_MIN;
   mPinBarNo3_Time   = INT_VALUE_MIN;

   trendCloud =  get_TrendCloud(global_Symbol,   // 通貨ペア
                                mTimeFrame,      // 時間軸
                                1 + mStartShift, // 雲の発生を判断するシフト
                                SMA20,           // 出力：雲の発生に判断したSMA20
                                SMA50            // 出力：雲の発生に判断したSMA50
                               );
                               
   if(trendCloud == UpTrend || trendCloud == DownTrend) {
      SMA05 = iMA( global_Symbol,     // 通貨ペア
                      mTimeFrame,  // 時間軸
                      5,           // MAの平均期間
                      0,           // MAシフト
                      MODE_SMA,    // MAの平均化メソッド
                      PRICE_CLOSE, // 適用価格
                      2 + mStartShift  // シフト
                  );

      bool flag_is_PinBar = false;
      bool flag_is_BigBody = false;
      // 2つ前が水色雲の時
      if(trendCloud == UpTrend) {
         // 2つ前に上向きピンバーが発生していれば、次が大陽線を確認する。
         flag_is_PinBar = is_PinBar(mTimeFrame, 
                                    BUY_SIGNAL, 
                                    2 + mStartShift, 
                                    PinBarPIN_MAX_PER);
         if(flag_is_PinBar == true) {
            // 1つ前が大陽線であり、2つ前の高値を抜いていれば、SMA05の位置に応じて、PinBarSignalが１，２
printf("[%d]PB No3でis_BigBody", __LINE__);
            
            flag_is_BigBody = is_BigBody(mTimeFrame, BUY_SIGNAL, 1 + mStartShift, PinBarBODY_MIN_PER);
            
            if(flag_is_BigBody == true) {

               if(NormalizeDouble(iHigh(global_Symbol, mTimeFrame, 2 + mStartShift),global_Digits) < NormalizeDouble(iHigh(global_Symbol, mTimeFrame, 1 + mStartShift), global_Digits ) ){
                  if(SMA05  >= SMA50 && SMA05 <= SMA20) {
                     mPinBarNo3_Signal = 1;
                     mPinBarNo3_Price  = iHigh(global_Symbol, mTimeFrame, 2 + mStartShift);
                     mPinBarNo3_Time   = iTime(global_Symbol, mTimeFrame, mStartShift);
                     
                     return true;
                  }
                  else if(SMA05  <= SMA50) {
                     mPinBarNo3_Signal = 2;
                     mPinBarNo3_Price  = iHigh(global_Symbol, mTimeFrame, 2 + mStartShift);
                     mPinBarNo3_Time   = iTime(global_Symbol, mTimeFrame, mStartShift);
                     
                     return true;
                  }
               }
            }
         }
      }
      // 2つ前が茶色雲の時SMA20 < mSMA50
      if(trendCloud == DownTrend) {
         // 2つ前に下向きピンバーが発生していれば、次が大陰線を確認する。
         flag_is_PinBar = is_PinBar(mTimeFrame, 
                                    SELL_SIGNAL, 
                                    2 + mStartShift, 
                                    PinBarPIN_MAX_PER);
         if(flag_is_PinBar == true) {
            // 1つ前が大陰線であり、2つ前の安値を下抜いていれば、SMA05の位置に応じて、PinBarSignalが3, 4
printf("[%d]PB No3でis_BigBody", __LINE__);
            
            flag_is_BigBody = is_BigBody(mTimeFrame, SELL_SIGNAL, 1 + mStartShift, PinBarBODY_MIN_PER);
            if(flag_is_BigBody == true) {
               if(NormalizeDouble(iLow(global_Symbol, mTimeFrame, 2 + mStartShift),global_Digits) > NormalizeDouble(iLow(global_Symbol, mTimeFrame, 1 + mStartShift), global_Digits ) ){
                  if(SMA05  >= SMA20 && SMA05 <= SMA50) {
                     mPinBarNo3_Signal = 3;
                     mPinBarNo3_Price  = iLow(global_Symbol, mTimeFrame, 2 + mStartShift);
                     mPinBarNo3_Time   = iTime(global_Symbol, mTimeFrame, mStartShift);
                     
                     return true;
                  }
                  else if(SMA05 >= SMA50) {
                     mPinBarNo3_Signal = 4;
                     mPinBarNo3_Price  = iLow(global_Symbol, mTimeFrame, 2 + mStartShift);
                     mPinBarNo3_Time   = iTime(global_Symbol, mTimeFrame, mStartShift);
                     
                     return true;
                  }
               }
            }
         }
      }
   }
   return false;
}



int entryPinBar_No5(int mShift) {
// №５：SMA50 ピンバー手法
// 本手法では便宜上SMA50よりもSMA20が上にある場合を「水色雲」とし、SMA50よりもSMA20が下にある場合は「茶色雲」とする。
// ・水色雲：SMA50よりSMA20が上にある上昇サイン
// ・茶色雲：SMA50よりSMA20が下にある下落サイン
// 
// 
// 買いの場合（1つ上の時間軸が下落でないこと）
// １．1つ前のシフトで、ローソク足が水色雲の中に潜る←ローソク足を実体部分(openとclose)とする。
// ２．同じく1つ前のシフトで、上向き矢印ピンバーが「水色雲下限」タッチ後（ピンバーのLowがSMA50を下回る）に出現する
// 　　ピンバーの高値がSMA50より下の場合は、対象外。
// ３．次の足の始値で買いエントリー
// 
// 売りの場合（1つ上の時間軸が上昇でないこと）
// １．1つ前のシフトで、ローソク足が茶色雲の中に潜る←ローソク足を実体部分(openとclose)とする。
// ２．同じく1つ前のシフトで、下向き矢印ピンバーが「茶色雲上限」タッチ後（ピンバーのHighがSMA50を上回る）に出現する
// ３．次の足の始値で売りエントリー
// 
// 利益確定
// １．エントリー後「+20pips」にリミットを設定する
// 
// 損切確定
// １．エントリー後、ピンバーの安値（買い）、高値（売り）まで10pips以下の場合「10pips」にストップを設定
// ２．ピンバー安値、ピンバーの高値までの距離が「10pips」以上離れている場合は、安値、高値から1pips余裕を見てストップを設定

   int mSignal  = NO_SIGNAL;
   int mTimeFrame = getTimeFrame(PinBarTimeframe);
//printf( "[%d]PB PinBarTimeframe>%d<　をmTimeFrame=>%d<に変換" , __LINE__, PinBarTimeframe, mTimeFrame);
      
   datetime nowDT = iTime(global_Symbol, mTimeFrame, mShift);
   
   int upper_TF = get_UpperLowerPeriod_ENUM_TIMEFRAMES(mTimeFrame, 1); // 1つ上の時間軸
//printf( "[%d]PB mTimeFrame>%d<　の1つ上の時間軸upper_TF=>%d<を入手" , __LINE__, mTimeFrame, upper_TF);

//   int flag_Trend; // 1つ上の時間軸のトレンド

   double SMA20 = DOUBLE_VALUE_MIN;
   double SMA50 = DOUBLE_VALUE_MIN;
   double open_i  = DOUBLE_VALUE_MIN;   
   double high_i  = DOUBLE_VALUE_MIN;   
   double low_i   = DOUBLE_VALUE_MIN;   
   double close_i = DOUBLE_VALUE_MIN;
   
   int trendCloud = NoTrend;
   int trendCloud_shift0 = NoTrend;

   double targetPrice = DOUBLE_VALUE_MIN; // 上向き矢印ピンバーの高値。現時点のASKがこの値以下であれば、買いを発注する。
   bool flag_is_PinBar; 
   
   // 
   // ロング
   // １．ローソク足が水色雲の中に潜る←ローソク足を実体部分(openとclose)とする。
   // ２．上向き矢印ピンバーが「水色雲下限」タッチ後（ピンバーのLowがSMA50を下回る）に出現するピンバーの高値がSMA50より下の場合は、対象外。
   // ３．次の足の始値で買いエントリー
   //
   SMA20 = DOUBLE_VALUE_MIN;
   SMA50 = DOUBLE_VALUE_MIN;
   trendCloud = get_TrendCloud(global_Symbol, mTimeFrame, 1 + mShift, SMA20, SMA50);
   // 水色の雲であること　SMA50 < SMA20
   if(trendCloud == UpTrend) { 
      // 1つ前のシフトが上向き矢印ピンバー（下髭）であること
      flag_is_PinBar = is_PinBar(mTimeFrame, 
                                 BUY_SIGNAL, 
                                 1 + mShift, 
                                 PinBarPIN_MAX_PER);
      if(flag_is_PinBar == true) {  // シフト1つ前が、上向き矢印ピンバー（下髭）
         // ピンバーの実体部分が、水色の雲の中にあること。また、下髭(low)が水色の雲の下の線(SMA50)を下抜けていること。
         open_i  = NormalizeDouble(iOpen(global_Symbol, mTimeFrame,  1 + mShift), global_Digits);
         close_i = NormalizeDouble(iClose(global_Symbol, mTimeFrame, 1 + mShift), global_Digits);
         low_i   = NormalizeDouble(iLow(global_Symbol, mTimeFrame,   1 + mShift), global_Digits);
         
         if(   (open_i > SMA50 && open_i < SMA20)   // シフト1つ前の始値が水色雲の中
            && (close_i > SMA50 && close_i < SMA20) // シフト1つ前の終値が水色雲の中→ピンバーの実体が水色雲の中
            && (low_i < SMA50) ) {                  // シフト1つ前が「水色雲下限」タッチしていることになる
//            return BUY_SIGNAL;
            // 水色雲の時点で上昇トレンドのため、1つ上のトレンドを見るのは廃止、
//            flag_Trend = get_Trend_EMA_PERIODH4(upper_TF, mShift);
//printf( "[%d]PB No5-buy" , __LINE__);
            
//            if(flag_Trend == UpTrend) {
//printf("[%d]PB entryPinBar_No5でロングシグナル>%s<", __LINE__,TimeToStr(iTime(global_Symbol, upper_TF, mShift)));
               return BUY_SIGNAL;
//            }
         }

      }
   }

   
   // 
   // ショート
   // １．ローソク足が茶色雲の中に潜る←ローソク足を実体部分(openとclose)とする。
   // ２．下向き矢印ピンバーが「茶色雲上限」タッチ後（ピンバーのHighがSMA50を上回る）に出現する
   // ３．次の足の始値で売りエントリー
   //
   // 茶色の雲であること　SMA50 > SMA20
   else if(trendCloud == DownTrend) {
//printf("[%d]PB entryPinBar_No5でショートシグナル>%s<に向けて茶色の雲である条件が成立", __LINE__,TimeToStr(iTime(global_Symbol, upper_TF, mShift)));
 
      // 1つ前のシフトが下向き矢印ピンバー（上髭）であること
      flag_is_PinBar = is_PinBar(mTimeFrame, 
                                 SELL_SIGNAL, 
                                 1 + mShift, 
                                 PinBarPIN_MAX_PER);
      if(flag_is_PinBar == true) {   // シフト1つ前が、下向き矢印ピンバー（上髭）
//printf("[%d]PB entryPinBar_No5でショートシグナル>%s<に向けて茶色の雲＋上ヒゲである条件が成立", __LINE__,TimeToStr(iTime(global_Symbol, upper_TF, mShift)));

         // ピンバーの実体部分が、水色の雲の中にあること。また、下髭(low)が水色の雲の下の線(SMA50)を下抜けていること。
         open_i  = NormalizeDouble(iOpen(global_Symbol,  mTimeFrame, 1 + mShift), global_Digits);
         close_i = NormalizeDouble(iClose(global_Symbol, mTimeFrame, 1 + mShift), global_Digits);
         high_i  = NormalizeDouble(iHigh(global_Symbol,  mTimeFrame, 1 + mShift), global_Digits);
         if((open_i < SMA50 && open_i > SMA20)     // ローソク足のOpen側が雲の中
            && (close_i < SMA50 && close_i > SMA20)// ローソク足のClose側が雲の中
            && (high_i > SMA50)                    // 上髭が、雲の天井を突破
            ) {
            // 茶色雲の時点で下降トレンドのため、1つ上のトレンドを見るのは廃止、
//            flag_Trend = get_Trend_EMA_PERIODH4(upper_TF, mShift);            
//            if(flag_Trend == DownTrend) {
//printf("[%d]PB entryPinBar_No5でショートシグナル>%s<", __LINE__,TimeToStr(iTime(global_Symbol, upper_TF, mShift)));

               return SELL_SIGNAL;
//            }
         }
         else {
//printf("[%d]PB entryPinBar_No5でショートシグナル>%s<に向けて茶色の雲＋上ヒゲである条件が成立していたが、ローソク実体が雲の中で上髭が天井突破を達成できず", __LINE__,TimeToStr(iTime(global_Symbol, upper_TF, mShift)));
         }
      }
      else {
//printf("[%d]PB entryPinBar_No5でショートシグナル>%s<に向けて茶色の雲だが、上ヒゲである条件が成立せず", __LINE__,TimeToStr(iTime(global_Symbol, upper_TF, mShift)));
      }
   }
   else {
      // 雲が水色でも茶色でもないときは、何もしない。
   } 
   
   return NO_SIGNAL;
}	




