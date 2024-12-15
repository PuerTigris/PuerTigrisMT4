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

//+------------------------------------------------------------------+
//|99.RandomTrade                                                 　　　   |
//+------------------------------------------------------------------+

int entryRandomTrade() {
   int mSignal  = NO_SIGNAL;
   int trend;
   bool Crossflag = false; // 測定したタイミングでクロスが発生していたらTrue。
   
   // 売買シグナルの候補を取得する。
   mSignal = entryRT_only_Rand();
   
   //
   // 何も制限しない
   //
   if(RTMethod == 0) {
      
//      mSignal = entryRT_only_Rand();
//     return mSignal;
   }
   //
   // EMAの上昇、下降を判断に追加する。上昇時のSELL禁止、加工時のBUY禁止
   //
   else if(RTMethod == 1) {
//      mSignal = entryRT_only_Rand();
      trend = NoTrend;
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸 
                                        1   // 何シフト前から判断するか
                                        ); 
      }
      
      // トレンドが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == UpTrend) {
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == DownTrend) {
         mSignal = NO_SIGNAL;
      }
   }

   //
   // MA短期と長期の位置を判断に追加する。MA短期が上の時のSELL禁止、MA短期が下の時のBUY禁止
   //
   else if(RTMethod == 2) {
//      mSignal = entryRT_only_Rand();
      // GCの時は1、DCの時は-1、それ以外は0を返す
      trend = 0;
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                            1,   // 何シフト前から判断するか
                            Crossflag // 判断した時点でクロスが発生していたらtrue
                              ); 
      }
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == 1) {
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == -1) {
         mSignal = NO_SIGNAL;
      }
      else {
      }
   }
   // RTMethod1 + 2 = 実質は２と同じ
   else if(RTMethod == 3) {
//      mSignal = entryRT_only_Rand();
      trend = NoTrend;
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸 
                                        1   // 何シフト前から判断するか
                                        ); 
      }
      // トレンドが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == UpTrend) {
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == DownTrend) {
         mSignal = NO_SIGNAL;
      }
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag // 判断した時点でクロスが発生していたらtrue
                              ); 
      }
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == 1) {
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == -1) {
         mSignal = NO_SIGNAL;
      }
      else {
      }

   }


   //
   // MACDとシグナルの位置を判断に追加する。MACDが上の時のSELL禁止、MACDが下の時のBUY禁止
   //
   else if(RTMethod == 4) {
      // GCの時は1、DCの時は-1、それ以外は0を返す
      trend = 0;
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag// 判断した時点でクロスが発生していたらtrue
                              ); 
      }
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == 1 && Crossflag == true) {
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == -1  && Crossflag == true) {
         mSignal = NO_SIGNAL;
      }
   }

   //
   // RTMethod1 + 4 = 実質は２と同じ
   //
   else if(RTMethod == 5) {
      // GCの時は1、DCの時は-1、それ以外は0を返す
      trend = NoTrend;
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸 
                                        1   // 何シフト前から判断するか
                                        ); 
      }
      
      // トレンドが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == UpTrend) {
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == DownTrend) {
         mSignal = NO_SIGNAL;
      }
            
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag// 判断した時点でクロスが発生していたらtrue
                              ); 
      }
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == 1 && Crossflag == true) {
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == -1  && Crossflag == true) {
         mSignal = NO_SIGNAL;
      }
   }

   //
   // RTMethod2 + 4
   //
   else if(RTMethod == 6) {

      trend = 0;
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag// 判断した時点でクロスが発生していたらtrue
                              ); 
      }
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == 1) {
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == -1) {
         mSignal = NO_SIGNAL;
      }
      else {
      }
      
            
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag// 判断した時点でクロスが発生していたらtrue
                              ); 
      }
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == 1 && Crossflag == true) {
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == -1  && Crossflag == true) {
         mSignal = NO_SIGNAL;
      }
   }

   //
   // RTMethod3 + 4
   //
   else if(RTMethod == 7) {

      trend = NoTrend;
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸 
                                        1   // 何シフト前から判断するか
                                        ); 
      }
      // トレンドが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == UpTrend) {
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == DownTrend) {
         mSignal = NO_SIGNAL;
      }
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag// 判断した時点でクロスが発生していたらtrue
                              ); 
      }
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == 1) {
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == -1) {
         mSignal = NO_SIGNAL;
      }
      else {
      }
      
            
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag// 判断した時点でクロスが発生していたらtrue
                              ); 
      }
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == 1 && Crossflag == true) {
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == -1  && Crossflag == true) {
         mSignal = NO_SIGNAL;
      }
   }
      
   else if(RTMethod == 8) {
//      mSignal = entryRT_only_Rand();
      // GCの時は1、DCの時は-1、それ以外は0を返す
      trend = 0;
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MacdGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag
                              ); 
      }
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == 1) {
printf( "[%d]RT 売りシグナルだったが、ゴールデンクロスのため、取り消し" , __LINE__);
      
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == -1) {
printf( "[%d]RT 買いシグナルだったが、デッドクロスのため、取り消し" , __LINE__);
         mSignal = NO_SIGNAL;
      }
 //     return mSignal;
   }
   //
   // MACDとシグナルの位置を判断に追加する。MACDが上の時のSELL禁止、MACDが下の時のBUY禁止。クロスが発生したときのみ発注する。
   //
   else if(RTMethod == 9) {
//      mSignal = entryRT_only_Rand();
      // GCの時は1、DCの時は-1、それ以外は0を返す
      trend = 0;
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MacdGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag
                              ); 
      }
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(mSignal == SELL_SIGNAL && trend == 1 && Crossflag == true) {
printf( "[%d]RT 売りシグナルだったが、ゴールデンクロスのため、取り消し" , __LINE__);
      
         mSignal = NO_SIGNAL;
      }
      else if(mSignal == BUY_SIGNAL && trend == -1  && Crossflag == true) {
printf( "[%d]RT 買いシグナルだったが、デッドクロスのため、取り消し" , __LINE__);
         mSignal = NO_SIGNAL;
      }
   }
   //
   // ランダムな取引とは関係ないパターン
   //
   // 101:get_Trend_EMA_PERIODH4で４時間足が上昇中は買い。下降中は売り。
   else if(RTMethod == 101) {
      trend = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸 
                                     1   // 何シフト前から判断するか
                                     ); 
     
      // トレンドが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == UpTrend) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == DownTrend) {
         mSignal = SELL_SIGNAL;
      }      
   }
   // 102:get_MAGCDCでMAがゴールデンクロス状態の時は買い。デッドクロス状態の時は売り。
   else if(RTMethod == 102) {
      trend = get_MAGCDC(0,  // 判断に使う時間軸 
                         1,   // 何シフト前から判断するか
                         Crossflag// 判断した時点でクロスが発生していたらtrue
                         ); 
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == 1) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == -1) {
         mSignal = SELL_SIGNAL;
      }     
   }      

   // 103=101+102:get_Trend_EMA_PERIODH4で４時間足が上昇中かつゴールデンクロスは買い。下降中かつデッドクロスは売り。
   else if(RTMethod == 103) {
      trend = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸 
                                     1   // 何シフト前から判断するか
                                     ); 
     
      // トレンドが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == UpTrend) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == DownTrend) {
         mSignal = SELL_SIGNAL;
      }      

      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                            1,   // 何シフト前から判断するか
                            Crossflag// 判断した時点でクロスが発生していたらtrue
                            ); 
         // GC/DCが、売買シグナルの同じ方向の時に現状維持。それ以外はNO_SIGNALで取り消し。
         if(mSignal == BUY_SIGNAL && trend == 1) {
            mSignal = BUY_SIGNAL;
         }
         else if(mSignal == SELL_SIGNAL && trend == -1) {
            mSignal = SELL_SIGNAL;
         }
         else {
            mSignal = NO_SIGNAL;
         }
      }
   }
   // 104:get_MAGCDCでMAがゴールデンクロス状態の時でクロスした直後は買い。デッドクロス状態の時でクロスした直後は売り。
   else if(RTMethod == 104 || RTMethod == 106) {
      trend = get_MAGCDC(0,  // 判断に使う時間軸 
                         1,   // 何シフト前から判断するか
                         Crossflag// 判断した時点でクロスが発生していたらtrue
                         ); 
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == 1 && Crossflag == true) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == -1 && Crossflag == true) {
         mSignal = SELL_SIGNAL;
      }
      else {
         mSignal = NO_SIGNAL;
      } 
   } 
   
   // 105=101+104:get_Trend_EMA_PERIODH4で４時間足が上昇中は買い。下降中は売り。
   //             かつ、get_MAGCDCでMAがゴールデンクロス状態の時でクロスした直後は買い。デッドクロス状態の時でクロスした直後は売り。
   else if(RTMethod == 105) {
      trend = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸 
                                     1   // 何シフト前から判断するか
                                     ); 
     
      // トレンドが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == UpTrend) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == DownTrend) {
         mSignal = SELL_SIGNAL;
      }      

      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                            1,   // 何シフト前から判断するか
                            Crossflag// 判断した時点でクロスが発生していたらtrue
                            ); 
         // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
         if(trend == 1 && Crossflag == true) {
            mSignal = BUY_SIGNAL;
         }
         else if(trend == -1 && Crossflag == true) {
            mSignal = SELL_SIGNAL;
         }
         else {
            mSignal = NO_SIGNAL;
         }
      }
   } 

   // 106=102+104:get_MAGCDCでMAがゴールデンクロス状態の時は買い。デッドクロス状態の時は売り。
   //             かつ、get_MAGCDCでMAがゴールデンクロス状態の時でクロスした直後は買い。デッドクロス状態の時でクロスした直後は売り。
   //             ※104と同じため、１０４にマージ

   // 107=101+106:get_MAGCDCでMAがゴールデンクロス状態の時は買い。デッドクロス状態の時は売り。
   //             かつ、get_MAGCDCでMAがゴールデンクロス状態の時でクロスした直後は買い。デッドクロス状態の時でクロスした直後は売り。
   //             かつ、get_Trend_EMA_PERIODH4で４時間足が上昇中は買い。下降中は売り。
   else if(RTMethod == 107) {
      trend = get_MAGCDC(0,  // 判断に使う時間軸 
                         1,   // 何シフト前から判断するか
                         Crossflag// 判断した時点でクロスが発生していたらtrue
                         ); 
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == 1 && Crossflag == true) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == -1 && Crossflag == true) {
         mSignal = SELL_SIGNAL;
      }
      else {
         mSignal = NO_SIGNAL;
      }

      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) { 
         trend = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸 
                                        1   // 何シフト前から判断するか
                                        ); 
        
         // トレンドが、売買シグナルと同じ方向の場合はそのまま。それ以外は、ＮＯ＿ＳＩＧＮＡＬで取消。
         if(mSignal == BUY_SIGNAL && trend == UpTrend) {
            mSignal = BUY_SIGNAL;
         }
         else if(mSignal == SELL_SIGNAL && trend == DownTrend) {
            mSignal = SELL_SIGNAL;
         }      
         else {
            mSignal = NO_SIGNAL;
         }
      }                  
   } 
   // 108=get_MACDGCDCでゴールデンクロス状態の時は買い。デッドクロス状態の時は売り。
   else if(RTMethod == 108) {
         trend = get_MacdGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag
                              ); 
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == 1) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == -1) {
         mSignal = SELL_SIGNAL;
      }
      else {
         mSignal = NO_SIGNAL;
      }
   }
   // 109=101+108:get_MACDGCDCでゴールデンクロス状態の時は買い。デッドクロス状態の時は売り。
   //             かつ、get_Trend_EMA_PERIODH4で４時間足が上昇中は買い。下降中は売り。
   else if(RTMethod == 109) {
         trend = get_MacdGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag
                              ); 
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == 1) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == -1) {
         mSignal = SELL_SIGNAL;
      }
      else {
         mSignal = NO_SIGNAL;
      }
      
      trend = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸 
                                     1   // 何シフト前から判断するか
                                     ); 
     
      // トレンドが、売買シグナルと同じ方向の場合はそのまま。それ以外は、ＮＯ＿ＳＩＧＮＡＬで取消。
      if(mSignal == BUY_SIGNAL && trend == UpTrend) {
         mSignal = BUY_SIGNAL;
      }
      else if(mSignal == SELL_SIGNAL && trend == DownTrend) {
         mSignal = SELL_SIGNAL;
      }      
      else {
         mSignal = NO_SIGNAL;
      }
   }
   // 110=102+108:get_MACDGCDCでゴールデンクロス状態の時は買い。デッドクロス状態の時は売り。
   //             かつ、get_MAGCDCでMAがゴールデンクロス状態の時でクロスした直後は買い。デッドクロス状態の時でクロスした直後は売り。
   else if(RTMethod == 110) {
         trend = get_MacdGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag
                              ); 
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == 1) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == -1) {
         mSignal = SELL_SIGNAL;
      }
      else {
         mSignal = NO_SIGNAL;
      }

      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                            1,   // 何シフト前から判断するか
                            Crossflag// 判断した時点でクロスが発生していたらtrue
                            ); 
         // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
         if(trend == 1 && Crossflag == true) {
            mSignal = BUY_SIGNAL;
         }
         else if(trend == -1 && Crossflag == true) {
            mSignal = SELL_SIGNAL;
         }
         else {
            mSignal = NO_SIGNAL;
         }
      }
   }   
   
   // 111=101+102+108:get_MACDGCDCでゴールデンクロス状態の時は買い。デッドクロス状態の時は売り。
   //                 かつ、get_MAGCDCでMAがゴールデンクロス状態の時でクロスした直後は買い。デッドクロス状態の時でクロスした直後は売り。
   else if(RTMethod == 111) {
         trend = get_MacdGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag
                              ); 
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == 1) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == -1) {
         mSignal = SELL_SIGNAL;
      }
      else {
         mSignal = NO_SIGNAL;
      }

      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                            1,   // 何シフト前から判断するか
                            Crossflag// 判断した時点でクロスが発生していたらtrue
                            ); 
         // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
         if(trend == 1 && Crossflag == true) {
            mSignal = BUY_SIGNAL;
         }
         else if(trend == -1 && Crossflag == true) {
            mSignal = SELL_SIGNAL;
         }
         else {
            mSignal = NO_SIGNAL;
         }
      }
            
      trend = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸 
                                     1   // 何シフト前から判断するか
                                     ); 
     
      // トレンドが、売買シグナルと同じ方向の場合はそのまま。それ以外は、ＮＯ＿ＳＩＧＮＡＬで取消。
      if(mSignal == BUY_SIGNAL && trend == UpTrend) {
         mSignal = BUY_SIGNAL;
      }
      else if(mSignal == SELL_SIGNAL && trend == DownTrend) {
         mSignal = SELL_SIGNAL;
      }      
      else {
         mSignal = NO_SIGNAL;
      }
   }   
   // 112=104+108:get_MACDGCDCでゴールデンクロス状態の時は買い。デッドクロス状態の時は売り。
   //             かつ、get_MAGCDCでMAがゴールデンクロス状態の時でクロスした直後は買い。デッドクロス状態の時でクロスした直後は売り。
   else if(RTMethod == 112 || RTMethod == 114) {
         trend = get_MacdGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag
                              ); 
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == 1) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == -1) {
         mSignal = SELL_SIGNAL;
      }
      else {
         mSignal = NO_SIGNAL;
      }

      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                            1,   // 何シフト前から判断するか
                            Crossflag// 判断した時点でクロスが発生していたらtrue
                            ); 
         // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
         if(trend == 1 && Crossflag == true) {
            mSignal = BUY_SIGNAL;
         }
         else if(trend == -1 && Crossflag == true) {
            mSignal = SELL_SIGNAL;
         }
         else {
            mSignal = NO_SIGNAL;
         }
      }
   }   
   
   // 113=101+104+108:get_MACDGCDCでゴールデンクロス状態の時は買い。デッドクロス状態の時は売り。
   //             かつ、get_MAGCDCでMAがゴールデンクロス状態の時でクロスした直後は買い。デッドクロス状態の時でクロスした直後は売り。
   else if(RTMethod == 113) {
         trend = get_MacdGCDC(0,  // 判断に使う時間軸 
                              1,   // 何シフト前から判断するか
                              Crossflag
                              ); 
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == 1) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == -1) {
         mSignal = SELL_SIGNAL;
      }
      else {
         mSignal = NO_SIGNAL;
      }

      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                            1,   // 何シフト前から判断するか
                            Crossflag// 判断した時点でクロスが発生していたらtrue
                            ); 
         // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
         if(trend == 1 && Crossflag == true) {
            mSignal = BUY_SIGNAL;
         }
         else if(trend == -1 && Crossflag == true) {
            mSignal = SELL_SIGNAL;
         }
         else {
            mSignal = NO_SIGNAL;
         }
      }
      
      trend = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸 
                                     1   // 何シフト前から判断するか
                                     ); 
     
      // トレンドが、売買シグナルと同じ方向の場合はそのまま。それ以外は、ＮＯ＿ＳＩＧＮＡＬで取消。
      if(mSignal == BUY_SIGNAL && trend == UpTrend) {
         mSignal = BUY_SIGNAL;
      }
      else if(mSignal == SELL_SIGNAL && trend == DownTrend) {
         mSignal = SELL_SIGNAL;
      }      
      else {
         mSignal = NO_SIGNAL;
      }
   }
   // 114=106+108:get_MAGCDCでMAがゴールデンクロス状態の時は買い。デッドクロス状態の時は売り。
   //             かつ、get_MAGCDCでMAがゴールデンクロス状態の時でクロスした直後は買い。デッドクロス状態の時でクロスした直後は売り。
   //             ※106は、104と同じため、１１２にマージ

   // 115=107+108=101+102+104+108:get_MAGCDCでMAがゴールデンクロス状態の時は買い。デッドクロス状態の時は売り。
   //             かつ、112=get_MAGCDCでMAがゴールデンクロス状態の時でクロスした直後は買い。デッドクロス状態の時でクロスした直後は売り。
   //             かつ、103=101+102:get_Trend_EMA_PERIODH4で４時間足が上昇中かつゴールデンクロスは買い。下降中かつデッドクロスは売り。
   else if(RTMethod == 115) {
      // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
      if(trend == 1) {
         mSignal = BUY_SIGNAL;
      }
      else if(trend == -1) {
         mSignal = SELL_SIGNAL;
      }
      else {
         mSignal = NO_SIGNAL;
      }

      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_MAGCDC(0,  // 判断に使う時間軸 
                            1,   // 何シフト前から判断するか
                            Crossflag// 判断した時点でクロスが発生していたらtrue
                            ); 
         // GC/DCが、売買シグナルの逆の場合にシグナルを取消。
         if(trend == 1 && Crossflag == true) {
            mSignal = BUY_SIGNAL;
         }
         else if(trend == -1 && Crossflag == true) {
            mSignal = SELL_SIGNAL;
         }
         else {
            mSignal = NO_SIGNAL;
         }
      }
      if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
         trend = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸 
                                        1   // 何シフト前から判断するか
                                        ); 
        
         // トレンドが、売買シグナルの逆の場合にシグナルを取消。
         if(trend == UpTrend) {
            mSignal = BUY_SIGNAL;
         }
         else if(trend == DownTrend) {
            mSignal = SELL_SIGNAL;
         }      
   
         if(mSignal == SELL_SIGNAL || mSignal == BUY_SIGNAL ) {
            trend = get_MAGCDC(0,  // 判断に使う時間軸 
                               1,   // 何シフト前から判断するか
                               Crossflag// 判断した時点でクロスが発生していたらtrue
                               ); 
            // GC/DCが、売買シグナルの同じ方向の時に現状維持。それ以外はNO_SIGNALで取り消し。
            if(mSignal == BUY_SIGNAL && trend == 1) {
               mSignal = BUY_SIGNAL;
            }
            else if(mSignal == SELL_SIGNAL && trend == -1) {
               mSignal = SELL_SIGNAL;
            }
            else {
               mSignal = NO_SIGNAL;
            }
         }
      }
   }   
         
   return mSignal;
}

int entryRT_only_Rand() {

   double randomValue = (double)(MathRand() % 3); // MathRandが、0～32767の整数を返す。
   

   // 乱数%3が、0ならば売り
   if(randomValue == 0) {
      return SELL_SIGNAL;
   }
   // 乱数%3が、1ならば買い
   else if(randomValue == 1) {
      return BUY_SIGNAL;
   }
   // 乱数%3が、2ならば様子見
   else if(randomValue == 2) {
      return NO_SIGNAL;
   }
   // 乱数%3が、0-2以外ならば様子見
   else  {
      return NO_SIGNAL;
   }
   
   return NO_SIGNAL;
}

// 2回乱数を発生させて、売買を判断する
int entryRT_only_Rand_Throw2Dices() {

   int randomMAX = 32767;
   int randomMIN = 0;
   
   double randomValue1 = (double)MathRand(); // MathRandが、0～32767の整数を返す。
   double randomValue2 = (double)MathRand(); // MathRandが、0～32767の整数を返す。

   // RTthreshold_PER = 50.0; // 売買判断をする閾値（threshold）。乱数(0～32767)が、32767 * RTthreshold_PER / 100以上なら売り。未満なら、買い。
   double judgeValue = (double)randomMAX * RTthreshold_PER / 100.0;

   // 2回発生させた乱数が、共に閾値より大きければ売り
   if(randomValue1 > judgeValue && randomValue2 > judgeValue) {
printf( "[%d]RT tickCount=%d randomValue1=%s > judgeValue=%s かつ　randomValue2=%s > judgeValue=%sのため、売りシグナル" , __LINE__,
   RTTickCount,
   DoubleToString(randomValue1, global_Digits),
   DoubleToString(judgeValue, global_Digits),
   DoubleToString(randomValue2, global_Digits),
   DoubleToString(judgeValue, global_Digits)
);
      return SELL_SIGNAL;
   }
   // 2回発生させた乱数が、共に閾値より小さければ買い
   else if(randomValue1 < judgeValue && randomValue2 < judgeValue) {
printf( "[%d]RT tickCount=%d randomValue1=%s < judgeValue=%s かつ　randomValue2=%s < judgeValue=%sのため、買いシグナル" , __LINE__,
   RTTickCount,
   DoubleToString(randomValue1, global_Digits),
   DoubleToString(judgeValue, global_Digits),
   DoubleToString(randomValue2, global_Digits),
   DoubleToString(judgeValue, global_Digits)
);
      return BUY_SIGNAL;
   }
   else {
printf( "[%d]RT tickCount=%d randomValue1=%s   randomValue2=%s   judgeValue=%s  シグナルなし" , __LINE__,
   RTTickCount,
   DoubleToString(randomValue1, global_Digits),
   DoubleToString(randomValue2, global_Digits),
   DoubleToString(judgeValue, global_Digits)
);
      return NO_SIGNAL;
   }

   return NO_SIGNAL;
}

// GCの時は1、DCの時は-1、それ以外は0を返す
int get_MacdGCDC(int mTimeframe ,  // 判断に使う時間軸 
                 int mShift,   // 何シフト前から判断するか
                 bool &mCross
                               ) {

   double mainValue    = NormalizeDouble(iMACD(NULL,mTimeframe,12,26,9,PRICE_CLOSE,MODE_MAIN,mShift), global_Digits);
   double signalValue  = NormalizeDouble(iMACD(NULL,mTimeframe,12,26,9,PRICE_CLOSE,MODE_SIGNAL,mShift), global_Digits);
   double mainValue2   = NormalizeDouble(iMACD(NULL,mTimeframe,12,26,9,PRICE_CLOSE,MODE_MAIN,mShift+1), global_Digits);
   double signalValue2 = NormalizeDouble(iMACD(NULL,mTimeframe,12,26,9,PRICE_CLOSE,MODE_SIGNAL,mShift+1), global_Digits);
   // ゴールデンクロスかデッドクロスの時、mCrossをtrue
   if(mainValue2 < signalValue2 && mainValue > signalValue) {
      mCross = true;   
   }
   else if(mainValue2 > signalValue2 && mainValue < signalValue) {
      mCross = true;   
   }
   else {
      mCross = false;
   }
printf( "[%d]RT mainValue=%s signalValue=%s   mainValue2=%s   signalValue2=%s " , __LINE__,
DoubleToStr(mainValue, global_Digits),
DoubleToStr(signalValue, global_Digits),
DoubleToStr(mainValue2, global_Digits),
DoubleToStr(signalValue2, global_Digits)
);
   
   // MACD線がシグナル線を上抜け→ゴールデンクロス（GC）
   // MACD線がシグナル線を下抜け→デッドクロス（DC）
   if(mainValue > signalValue) {
      return 1;
   }
   else if(mainValue < signalValue) {
      return -1;
   }
   else {
      return 0; 
   }
   
   return 0;
}


// GCの時は1、DCの時は-1、それ以外は0を返す
int get_MAGCDC(int mTimeframe ,  // 判断に使う時間軸 
                 int mShift,   // 何シフト前から判断するか
                 bool &mCross  // 判断した時点でクロスが発生していたらtrue
                               ) {
   double mainValue    = NormalizeDouble(iMA(NULL,PERIOD_CURRENT,25,0,MODE_SMA,PRICE_CLOSE,mShift) , global_Digits);
   double signalValue  = NormalizeDouble(iMA(NULL,PERIOD_CURRENT,75,0,MODE_SMA,PRICE_CLOSE,mShift), global_Digits);
   double mainValue2   = NormalizeDouble(iMA(NULL,PERIOD_CURRENT,25,0,MODE_SMA,PRICE_CLOSE,mShift+1), global_Digits);
   double signalValue2 = NormalizeDouble(iMA(NULL,PERIOD_CURRENT,75,0,MODE_SMA,PRICE_CLOSE,mShift+1), global_Digits);
   // ゴールデンクロスかデッドクロスの時、mCrossをtrue
   if(mainValue2 < signalValue2 && mainValue > signalValue) {
      mCross = true;   
   }
   else if(mainValue2 > signalValue2 && mainValue < signalValue) {
      mCross = true;   
   }
   else {
      mCross = false;
   }
   
   // MA短期が長期線を上抜け→ゴールデンクロス（GC）
   // MA短期が長期線を下抜け→デッドクロス（DC）
   if(mainValue > signalValue) {
      return 1;
   }
   else if(mainValue < signalValue) {
      return -1;
   }
   else {
      return 0; 
   }
   
   return 0;
}


