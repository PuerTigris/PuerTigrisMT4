//#property strict	
// カギの説明
// https://keexodia-fx.com/keyleg/カギ足の作り方
// 1. 一定値幅を決める。
// 2. 決めた値幅が動いたら、動いた方向に垂直線を引く
//    もし動いた値幅が順方向ならば、垂直線を伸ばす。
// 3. 逆方向に動いたならば、1マス右に線を引き垂直線を書く。その時、方向は2．と逆方向に書く。

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
double KAGIPips    = 30.0;  // このPIPS数を超えた上下があった場合に、カギを更新する。
int    KAGISize    = 20; // 何本前のシフトからカギの計算をするか。
int    KAGIMethod  = 2;  // 1:一段抜きで売買、2:三尊で売買、3:五瞼で売買
*/

double KagiBuff[1000];
string KagiBuffTime[1000];  // デバッグ用に用意したKagiBuffの更新時間。


//+------------------------------------------------------------------+
//|   No.17 entryKAGI()                                               |
//+------------------------------------------------------------------+  
int entryKAGI() {

   int i;
   int size1 = 0;
   int KAGIPorog1 = 0;
   int KagiBuffShift=0;
   int ticket_num = 0;
   double sl = 0.0;
   double tp = 0.0;
   int Ichidan  = 13;
   int Sanzon_1 = 11;
   int Sanzon_2 = 9;
   int Goken_1  = 7;
   int Goken_2  = 5;
   int Ryomado_1 = 3;
   int Ryomado_2 = 1;
   double ATR_1 = 0.0;
	
   if(KAGISize<51 && KAGISize>2) {
      size1=KAGISize;
   }
   else {
      if(KAGISize<3) {
         size1=3;
      }
      //----
      if(KAGISize>50) {
         size1=50;
      }
   }

   if( (KAGIMethod > 3) || (KAGIMethod < 1) ) {
      return NO_SIGNAL;
   }

   if(size1 < 1) {
      return NO_SIGNAL;
   }
   int limit = size1;                       // 例えば、limit = 50
   ArrayInitialize(KagiBuff,0.0);
   KagiBuff[KagiBuffShift] = Close[limit-1];  // KagiBuff[0]を、カギを計算する出発点であるClose[49=50番目のシフト]とする。
   KagiBuffTime[KagiBuffShift] = TimeToStr(Time[limit-1]); 

//----
   for(i=limit-2; i>=1; i--) {              // 例えば、limitは、48～0
      double close_i = NormalizeDouble(Close[i], global_Digits);   

      // 48番目から順にCloseに着目し、それが直前のKagiBuff[KagiBuffShift]から見て、KAGIPips*global_Points以上、上下していれば、
      // KagiBuff[KagiBuffShift + 1]に着目したCloseの値を代入する。
      // なお、KagiBuffShift == 0の時は、直前のKagiBuffが存在しないため、出発点のCloseであるclose_iと比較する。
      //----
      if(KagiBuffShift == 0) {
         if(NormalizeDouble(close_i, global_Digits) > NormalizeDouble(KagiBuff[KagiBuffShift], global_Digits) + NormalizeDouble(KAGIPips*global_Points, global_Digits)){
            KagiBuffShift++;
            KagiBuff[KagiBuffShift] = close_i;
            KagiBuffTime[KagiBuffShift] = TimeToStr(iTime(global_Symbol, 0,i)); 
         }
         else if(NormalizeDouble(close_i, global_Digits) < NormalizeDouble(KagiBuff[KagiBuffShift], global_Digits) - NormalizeDouble(KAGIPips*global_Points, global_Digits)) {
            KagiBuffShift++;
            KagiBuff[KagiBuffShift]=NormalizeDouble(close_i, global_Digits) ;
            KagiBuffTime[KagiBuffShift] = TimeToStr(iTime(global_Symbol, 0,i)); 
         }
         else {
         }
      }
      //----
      if(KagiBuffShift > 1) {
         // 直前のKagiBuff[KagiBuffShift - 1]より現時点のKagiBuff[KagiBuffShift]の方が大きく、
         // 上昇中（肩を更新中）の時。
         if(NormalizeDouble(KagiBuff[KagiBuffShift], global_Digits)  > NormalizeDouble(KagiBuff[KagiBuffShift - 1], global_Digits) ) { 
            // 直近のclose_iの方が、現時点のKagiBuff[KagiBuffShift]より大きければ、close_iで更新する。＝上昇の継続。
            if(NormalizeDouble(close_i, global_Digits) > NormalizeDouble(KagiBuff[KagiBuffShift], global_Digits)) {
               KagiBuff[KagiBuffShift] = NormalizeDouble(close_i, global_Digits) ;
               KagiBuffTime[KagiBuffShift] = TimeToStr(iTime(global_Symbol, 0,i)); 
            }
            // 直近のclose_iが、現時点のKagiBuff[KagiBuffShift]よりKAGIPips*global_Points小さければ、
            // KagiBuff[KagiBuffShift + 1]をclose_iとする。　＝　上昇中から、下降中に転換したことになる。
            if(NormalizeDouble(close_i, global_Digits) < NormalizeDouble(KagiBuff[KagiBuffShift], global_Digits) - NormalizeDouble(KAGIPips * global_Points, global_Digits)){
               KagiBuffShift++;
               KagiBuff[KagiBuffShift] = NormalizeDouble(close_i, global_Digits);
               KagiBuffTime[KagiBuffShift] = TimeToStr(iTime(global_Symbol, 0,i)); 
            }
         }
         //----
         // 直前のKagiBuff[KagiBuffShift - 1]より現時点のKagiBuff[KagiBuffShift]の方が小さく、
         // 下降中（腰を更新中）の時。
         if(NormalizeDouble(KagiBuff[KagiBuffShift], global_Digits) < NormalizeDouble(KagiBuff[KagiBuffShift-1], global_Digits)){
            // 直近のclose_iの方が、現時点のKagiBuff[KagiBuffShift]より小さければ、close_iで更新する。＝下降の継続。
            if(NormalizeDouble(close_i, global_Digits) < NormalizeDouble(KagiBuff[KagiBuffShift], global_Digits)) {
               KagiBuff[KagiBuffShift] = NormalizeDouble(close_i, global_Digits);
               KagiBuffTime[KagiBuffShift] = TimeToStr(iTime(global_Symbol, 0,i)); 
            }
            // 直近のclose_iが、現時点のKagiBuff[KagiBuffShift]よりKAGIPips*global_Points大きければ、
            // KagiBuff[KagiBuffShift + 1]をclose_iとする。　＝　下降中から、上昇中に転換したことになる。
            if(NormalizeDouble(close_i, global_Digits) > NormalizeDouble(KagiBuff[KagiBuffShift], global_Digits) + NormalizeDouble(KAGIPorog1*Point, global_Digits)) {
               KagiBuffShift++;
               KagiBuff[KagiBuffShift] = NormalizeDouble(close_i, global_Digits);
               KagiBuffTime[KagiBuffShift] = TimeToStr(iTime(global_Symbol, 0,i)); 
            }
         }
      }
   }
/*
printf( "[%d]テスト　KagiBuffShift=0が直近か、最古かを確認する", __LINE__);
printf( "[%d]テスト　基準日=%s", __LINE__, TimeToStr(Time[0]));
for(int ii = 0; ii <= KagiBuffShift; ii++) {
printf( "[%d]テスト　KagiBuff[%d]=%s  KagiBuffTime[%d]=%s]", __LINE__, ii, DoubleToStr(KagiBuff[ii]),ii, DoubleToStr(KagiBuffTime[ii] ));
}
*/
   double KAGILots = 0.0;
   double UPWaistBuf = 0.0;
   double DOWNWaistBuf = 0.0;
   double close_0 = NormalizeDouble(Close[0], global_Digits);
   
   int BuySellSignal = NO_SIGNAL;

   // 直近のKagiBuff[KagiBuffShift]が肩か腰かを判断する。
   // ・直近が腰（底）で、close_0がそれよりも大きく、条件を満たしていれば、買い。
   // ・直近が肩（天井）で、close_0がそれよりも小さく、条件を満たしていれば、売り。
   // カギのパターンと売買
   // https://www.fxnav.net/kagi_chart/
   // 一段抜き(カギ足の一段抜き)
   //   - チャートパターンであるダブルトップ・ダブルボトムの形です。ネックラインとなる「腰」超えで売り、「肩」超えで買いとなります。  
   // 三尊・逆三尊(カギ足の三尊・逆三尊)
   //   - ヘッド＆ショルダーの形です。ネックライン超えで売買します。
   // 五瞼（ごけん）カギ足の五瞼
   //   - ⑤が、①と④の中心を割り込むことなく上昇・下落すると強いシグナルとなります。

   //
   // 買い
   //
   if(KagiBuffShift >= 1 && NormalizeDouble(KagiBuff[KagiBuffShift], global_Digits) < NormalizeDouble(KagiBuff[KagiBuffShift - 1], global_Digits)) {
      //・直近が腰（底）のため、close_0がそれよりも大きく、条件を満たしていれば、買い
      // 
      //  一段抜き (買い）
      // |
      // |        ↑直前のS(肩)を抜けたので、買い
      // |   __   |
      // |  |S |  |← KagiBuff[KagiBuffShift - 1]
      // |  |  |  |
      // |__|  |W |← KagiBuff[KagiBuffShift]
      // KAGIMethodが1の時のみ該当
      if(KAGIMethod == 1 && NormalizeDouble(close_0, global_Digits) > NormalizeDouble(KagiBuff[KagiBuffShift - 1], global_Digits)) {
         BuySellSignal = BUY_SIGNAL;
      }
      //  三尊 (買い）
      // |                  ↑  直前の肩を2つ抜けたので、買い
      // |           ___    |← S1=肩1 KagiBuff[KagiBuffShift - 1] 
      // |   ___    |S1 |   |
      // |  |S2 |   |   |   |← S2=肩2 KagiBuff[KagiBuffShift - 3]
      // |  |   |   |   |   |
      // |__|   |   |   |W1 |← W1=腰1 KagiBuff[KagiBuffShift]
      //        |W2 |        ← W2=腰2 KagiBuff[KagiBuffShift - 2]
      // KAGIMethodが2の時に、該当。KAGIMethodが1であっても、より厳しい条件のこれを満たしていれば、取引を許可する。
      if(KagiBuffShift >= 3 && KAGIMethod <= 2 
         && NormalizeDouble(close_0, global_Digits) > NormalizeDouble(KagiBuff[KagiBuffShift - 1], global_Digits) 
         && NormalizeDouble(close_0, global_Digits) > NormalizeDouble(KagiBuff[KagiBuffShift - 3], global_Digits)) {
         BuySellSignal = BUY_SIGNAL;
      }
      //  五瞼 (買い）⑤が、①と④の中心を割り込むことなく上昇
      // |            ↑  直前の肩④つ抜けたので、買い
      // |        __  | 
      // |  __   |④ | |← ④ KagiBuff[KagiBuffShift - 1]
      // | |② |  |  | |← ② KagiBuff[KagiBuffShift - 3]
      // | |  |  |  |⑤|← ⑤ KagiBuff[KagiBuffShift]
      // |①|  |  |        ← ① KagiBuff[KagiBuffShift - 4]
      //      |③_|        ← ③ KagiBuff[KagiBuffShift - 2]
      // KAGIMethodが3の時に、該当。KAGIMethodが1, 2であっても、より厳しい条件のこれを満たしていれば、取引を許可する。
      if(KagiBuffShift >= 4 &&  (KAGIMethod <= 3) 
           && (NormalizeDouble(close_0, global_Digits) > NormalizeDouble(KagiBuff[KagiBuffShift - 1], global_Digits))  // 直前の肩④つ抜けたので、買い
           && ( NormalizeDouble(KagiBuff[KagiBuffShift], global_Digits) > (NormalizeDouble(KagiBuff[KagiBuffShift - 1], global_Digits) + NormalizeDouble(KagiBuff[KagiBuffShift - 4], global_Digits)) / 2 ) //⑤が、①と④の中心を割り込むことなく上昇
         ) {
            BuySellSignal = BUY_SIGNAL;
      }
   }
   //
   // 売り
   //
   else if(KagiBuffShift >= 1 && NormalizeDouble(KagiBuff[KagiBuffShift], global_Digits) > NormalizeDouble(KagiBuff[KagiBuffShift - 1], global_Digits)) {
      //・直近が肩（天井）のため、close_0がそれよりも小さく、条件を満たしていれば、売り
      // 
      //  一段抜き (売り）
      //  __
      // |  |  __ 
      // |  | |S |← KagiBuff[KagiBuffShift]
      // |  | |  |
      // |  |W|  |← KagiBuff[KagiBuffShift - 1]
      // |       |    
      //         ↓直前のW=腰を抜けたので、売り
      if(KAGIMethod == 1 && NormalizeDouble(close_0, global_Digits) < NormalizeDouble(KagiBuff[KagiBuffShift - 1], global_Digits)) {
         BuySellSignal = SELL_SIGNAL;
      }
      //  三尊 (売り）
      //              
      //  ___             ___
      // |  |    ___    |肩1|        ←肩1 KagiBuff[KagiBuffShift]   
      // |  |   |肩2|   |   |        ←肩2 KagiBuff[KagiBuffShift - 2] 
      // |  |腰2|   |   |   |        ←腰2 KagiBuff[KagiBuffShift - 3]
      // |  |___|   |   |   |
      // |          |腰1|   |        ←腰1 KagiBuff[KagiBuffShift - 1] 
      //                     |
      //                     ↓直前の腰を2つ抜けたので、売り
      // KAGIMethodが2の時に、該当。KAGIMethodが1であっても、より厳しい条件のこれを満たしていれば、取引を許可する。
      if(KagiBuffShift >= 3 && KAGIMethod <= 2 
         && NormalizeDouble(close_0, global_Digits) < NormalizeDouble(KagiBuff[KagiBuffShift - 1], global_Digits) 
         && NormalizeDouble(close_0, global_Digits) < NormalizeDouble(KagiBuff[KagiBuffShift - 3], global_Digits)) {
         BuySellSignal = SELL_SIGNAL;
      }
      //  五瞼 (売り）
      //              
      //  ___             
      // |①|    ___           ←① KagiBuff[KagiBuffShift - 4] 
      // |  |   |③ |          ←③ KagiBuff[KagiBuffShift - 2]
      // |  |   |   |   |⑤ |  ←⑤ KagiBuff[KagiBuffShift]
      // |  |②_|   |   |   |  ←② KagiBuff[KagiBuffShift - 3]
      // |          |④ |   |  ←④ KagiBuff[KagiBuffShift - 1] 
      //                     |
      //                     ↓直前の腰④を抜けたので、売り
      // KAGIMethodが3の時に、該当。KAGIMethodが1, 2であっても、より厳しい条件のこれを満たしていれば、取引を許可する。
      if( KagiBuffShift >= 4 && (KAGIMethod <= 3)
           && (NormalizeDouble(close_0, global_Digits) < NormalizeDouble(KagiBuff[KagiBuffShift - 1], global_Digits) )  
           && (NormalizeDouble(KagiBuff[KagiBuffShift], global_Digits) < (NormalizeDouble(KagiBuff[KagiBuffShift - 1], global_Digits)  + NormalizeDouble(KagiBuff[KagiBuffShift - 4], global_Digits) ) / 2    )     ){
         BuySellSignal = SELL_SIGNAL;
      }
   }

//----
   return BuySellSignal ;
  }
  


