//#property strict	
/*
【基本的な考え方１】
参考資料不明。
赤い転換線が青い基準線を下から上に抜けることを好転。そしてロウソク足が雲の上に抜けて、
遅行線がロウソク足を上回ると三役好転といい非常に強い買いサイン

 売りサインはこれと逆で転換線が基準線を上から下に抜け、
ロウソク足が雲の下に抜け、遅行線がロウソク足を下回ると
三役逆転という強い売りサイン

【基本的な考え方２】
https://ichimokukinkohyo.net/kumo-form
・『一目均衡表の雲』というのは、先行スパン1と先行スパン2の間に出来た空間
①一般的にはローソク足が雲を上抜けたらトレンドが転換したと考えて買い。
　反対に雲を下抜けたら売り
②上昇トレンド中に押し目をつけて雲にタッチした時に雲が分厚ければ買い。
　押し目を買うにしても、右端の雲の先端が厚いのか？細いのかを確認
③先端の雲が細くて上を向いている場合は、その後も調整が入らずに伸びていく可能性が高い。
④上昇トレンドが続いている環境でも、雲が広がって分厚くなっていなければ、まだ上昇が続く。
　→上の③④から、そこそこ上昇してるのに雲が細い場合は、ポジションをキープしたり、買い増し
・エントリーする時間足だけではなく、上位足の雲の厚さも必ず確認
・基本的に、雲のねじれはそれまでのトレンドが一旦崩れたという段階
　→雲がねじれた後で、価格が高値を切り上げて、更に安値を切り下げてきたらトレンドが転換。
・経験と感覚でいうと、例えばユーロドルの場合、5分足だと雲の幅が5pip以下なら細くて10pips以上なら分厚い。
　1時間足だと25pips以下なら細くて50pips以上なら分厚い。
　日足だと150pips以下なら細くて250pips以上なら分厚い。
・ローソク足が雲より下の時に転換線を終値で上抜けたら買い。
　ローソク足が雲より上の時に転換線を終値で下抜けたら売り
・遅行線がローソク足を下から上抜けたら買い
　遅行線がローソク足を上から下抜けたら売り
・三役好転とは、
　1) 転換線が基準線を上抜ける
     転換線が基準線を上抜けた時は、短期トレンドが上昇に転換したことを示す。
  2) 遅行線がローソク足を上抜ける
     遅行線がローソク足を上抜けた時は、中期トレンドが上昇に転換したことを示す。
  3) ローソク足が雲を上抜ける
     ローソク足が雲を上抜けた時は、長期トレンドが上昇トレンドに転換したことを示す。
　ダマシを防ぐため、
  a. 直近の戻り高値を上抜けるのを確認すること
  b. 価格が押し目を付けて最後の戻り高値まで落ちてくるのを待つ
     そのラインまで落ちてこないで上昇していく事もあるし、逆に少し下抜けてから反発していくケースもあるが、
　　 とにかくそのライン付近まで価格が落ちてくるのを待つ。
　　 最後の戻り高値のサポート地点と先行スパン1又は先行スパン2が、雲を上抜けた後の押し目近くにある場合は、そこが強力なサポート。

【実装ルール】
https://manabu-blog.com/mt4-ichimoku-kinkohyo-ea 
１．基準線と転換線のクロス　＝ ICHIMOKU_METHOD = 1
買い：転換線が基準線を上抜けたとき
売り：転換線が基準線を下抜けたとき

２．遅行スパンと価格のクロス＝ ICHIMOKU_METHOD = 2。ただし、上記１も満たすこと。
買い：遅行スパンが26本前の価格を上抜けたとき
売り：遅行スパンが26本前の価格を下抜けたとき

３．雲のブレイクアウト　　　＝ ICHIMOKU_METHOD = 3。ただし、上記１、２も満たすこと。
買い：価格が雲を上昇ブレイクアウトしたとき
売り：価格が雲を下降ブレイクアウトしたとき
※上記１～３がすべて成立すれば、三役好転。

４．基準線と価格のクロス　　＝ ICHIMOKU_METHOD = 4。ただし、上記１～３も満たすこと。
買い：価格が基準線を上抜け＆基準線が雲を上回るとき
売り：価格が基準線を下抜け＆基準線が雲を下回るとき

５．雲のねじれ　　　　　　　＝ ICHIMOKU_METHOD = 5。ただし、上記１～４も満たすこと。
買い：先行スパンAが先行スパンBを上回るとき(雲の陽転)
売り：先行スパンAが先行スパンBを下回るとき(雲の陰転)
→【基本的な考え方２】雲がねじれた後で、価格が高値を切り上げて、更に安値を切り上げてきたらトレンドが転換。

上記に１～５に共通して、MACDがゴールデンクロスの位置またはデッドクロスの位置になることを追加。

【ぜひ試してみて！】FXでの一目均衡表のおすすめ設定期間は(7,21,42)！
*/


//-----------------------------------------------------------------+	
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
int ICHIMOKU_SPANTYPE = 1; // 0or1。一目均衡表データを取得するための設定値セット。
                           // 0の時、転換線期間=9、基準線期間=26、先行スパン期間=52
                           // 1の時、転換線期間=7、基準線期間=21、先行スパン期間=42
int ICHIMOKU_METHOD = 5;  //1～5
                          // １．基準線と転換線のクロス　＝ ICHIMOKU_METHOD = 1
                          // ２．遅行スパンと価格のクロス＝ ICHIMOKU_METHOD = 2。ただし、上記１も満たすこと。
                          // ３．雲のブレイクアウト　　　＝ ICHIMOKU_METHOD = 3。ただし、上記１、２も満たすこと。
                          // ４．基準線と価格のクロス　　＝ ICHIMOKU_METHOD = 4。ただし、上記１～３も満たすこと。
                          // ５．雲のねじれ　　　　　　　＝ ICHIMOKU_METHOD = 5。ただし、上記１～４も満たすこと。
*/
//double ICHIMOKU_kumo = 0.9; //雲の厚さがこの値以上であれば、厚いとみなす。
//int ICHIMOKU_TF = 0; //0から9。2は、PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。

//+------------------------------------------------------------------+
//|  No.16 entryIchimokuMACD()                                            |
//+------------------------------------------------------------------+
// 返り値：BUY_SIGNAL, SELL_SIGNAL, NO_SIGNALのいずれか。
  
int entryIchimokuMACD() {
   int mICHIMOKU_Tenkan =  9; //転換線期間
   int mICHIMOKU_Kijun  = 26; //基準線期間
   int mICHIMOKU_Senko  = 52; //先行スパン期間
   int buysellFlag = NO_SIGNAL;

   if(ICHIMOKU_SPANTYPE == 0) {
      // 初期値と同じ
      mICHIMOKU_Tenkan =  9; //転換線期間
      mICHIMOKU_Kijun  = 26; //基準線期間
      mICHIMOKU_Senko  = 52; //先行スパン期間
   }
   else if(ICHIMOKU_SPANTYPE == 1) {
      mICHIMOKU_Tenkan =  7; //転換線期間
      mICHIMOKU_Kijun  = 21; //基準線期間
      mICHIMOKU_Senko  = 42; //先行スパン期間
   }
   else {
      // 後続処理をせず、NO_SIGNALを返す。
      return NO_SIGNAL;
   }



   //MACD
   double MACD1   = iMACD(global_Symbol,0,26,52,9,0,0,1);
   double Signal1 = iMACD(global_Symbol,0,26,52,9,0,1,1);

   double tenkan1 = 0.0;
   double tenkan2 = 0.0;
   double kijun1 = 0.0;
   double kijun2 = 0.0;
   double chikou = 0.0;
   double close_Shift26 = 0.0;
   double spana = 0.0;
   double spanb = 0.0;
   double close_Shift1 = 0.0;

   int mTimeFrame  = global_Period; // 移動平均を計算するための時間軸
   int mStartShift = 1; // 計算開始位置
   int lastGC = INT_VALUE_MIN; // 直近のゴールデンクロスが発生したシフト
   int lastDC = INT_VALUE_MIN; // 直近のデッドクロスが発生したシフト
 
   //
   //オーダータイミング
   //
   // ※処理時間短縮を目的として、iIchimokuの呼び出しを減らすため、ソースコードが重複している。
   // 
   // 買いシグナル
   // 共通。MACDがゴールドクロス後＝MACD > SIGNAL
   if(NormalizeDouble(MACD1, global_Digits*2) > NormalizeDouble(Signal1, global_Digits*2)) {

      // １．基準線と転換線のクロス　＝ ICHIMOKU_METHOD = 1
      //  買い：転換線が基準線を上抜けたとき
      //  売り：転換線が基準線を下抜けたとき
      //  20220411 上抜け（下抜け）た瞬間だけでなく、比較する2点が共に上回っている（下回っている）場合も条件を満たすこととする。
      //  20220412 転換線が基準線を上回ることが無い事態が発生。GCがDCより近い(GC<DC)の時を買いとする。
      if(ICHIMOKU_METHOD >= 1) {
         mTimeFrame  = global_Period;
         mStartShift = 1; 
         lastGC      = INT_VALUE_MIN;
         lastDC      = INT_VALUE_MIN;
         bool flag = getLastIchi_Cross(mTimeFrame, // 入力：移動平均を計算するための時間軸
                                       mStartShift, // 入力：計算開始位置
                                       lastGC,    // 出力：直近のゴールデンクロスが発生したシフト
                                       lastDC     // 出力：直近のデッドクロスが発生したシフト
                                      );
                                      
         if(flag == false) {
            printf( "[%d]ICHI GC, DC発見できず lastGC=%d lastDC=%d" , __LINE__, lastGC, lastDC);
            return NO_SIGNAL;
         }
         else if(lastGC < lastDC) { // GCがDCより近い(GC<DC)の時、買いシグナル仮置き
            buysellFlag = BUY_SIGNAL;
            
         }
         else {
            buysellFlag = NO_SIGNAL;
         }
/*20220411
         // 転換線
         tenkan1 = iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_TENKANSEN, 1);
         if(tenkan1 <= 0.0) {
            return NO_SIGNAL;
         }
         tenkan2 = iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_TENKANSEN, 2);
         if(tenkan2 <= 0.0) {
            return NO_SIGNAL;
         }

         // 基準線
         // シフト1
         kijun1 =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_KIJUNSEN, 1);
         if(kijun1 <= 0.0) {
            return NO_SIGNAL;
         }
         // シフト2
         kijun2 =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_KIJUNSEN, 2);
         if(kijun2 <= 0.0) { 
            return NO_SIGNAL;
         }
      
         // 買い：転換線が基準線を上抜けたとき
         if( (NormalizeDouble(kijun2, global_Digits) >= NormalizeDouble(tenkan2, global_Digits) 
               && NormalizeDouble(kijun1, global_Digits) <= NormalizeDouble(tenkan1, global_Digits))
            ||
             (NormalizeDouble(kijun2, global_Digits) <= NormalizeDouble(tenkan2, global_Digits)      // 20220411転換線2点が共に上回っている時を追加
               && NormalizeDouble(kijun1, global_Digits) <= NormalizeDouble(tenkan1, global_Digits))
          ) {
            buysellFlag = BUY_SIGNAL;
         } 
         else { 
printf( "[%d]ICHI 方法=1のBUY不成立-1 基準線2=%s   転換線2=%s" , __LINE__, DoubleToStr(kijun2, global_Digits), DoubleToStr(tenkan2, global_Digits) );
printf( "[%d]ICHI 方法=1のBUY不成立-2 基準線1=%s   転換線1=%s" , __LINE__, DoubleToStr(kijun1, global_Digits), DoubleToStr(tenkan1, global_Digits) );
            buysellFlag = NO_SIGNAL;
         }
*/

      } //      if(ICHIMOKU_METHOD >= 1) 


      // ２．遅行スパンと価格のクロス＝ ICHIMOKU_METHOD = 2。ただし、上記１も満たすこと。
      // 買い：遅行スパンが26本前の価格を上抜けたとき
      // 売り：遅行スパンが26本前の価格を下抜けたとき
      if(ICHIMOKU_METHOD >= 2 && buysellFlag == BUY_SIGNAL) {
      
         // 遅行スパン シフトは+26することhttps://investment-vmoney.com/archives/4688
         chikou = iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_CHIKOUSPAN, 26 + 1); //
         if(chikou <= 0.0) {
            return NO_SIGNAL;
         }
         
         // 26本前の価格
         close_Shift26 = Close[26 + 1];
         if(close_Shift26 <= 0.0) {
            return NO_SIGNAL;
         }

         // 買い：遅行スパンが26本前の価格を上抜けたとき
         if(NormalizeDouble(chikou, global_Digits) >= NormalizeDouble(close_Shift26, global_Digits) ) {
            buysellFlag = BUY_SIGNAL;
         }
         else { 
            buysellFlag = NO_SIGNAL;
         }
      } //      if(ICHIMOKU_METHOD >= 2) 

      // ３．雲のブレイクアウト　　　＝ ICHIMOKU_METHOD = 3。ただし、上記１、２も満たすこと。
      // 買い：価格が雲を上昇ブレイクアウトしたとき
      // 売り：価格が雲を下降ブレイクアウトしたとき
      // 20220412 ブレイクアウトをシフト１，２共に上回っている（下回っている）時も可とした。結果、シフト１の比較のみとした。
      if(ICHIMOKU_METHOD >= 3 && buysellFlag == BUY_SIGNAL) {
      
         // 先行スパンA（雲を形成する線の1つ）
         spana =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_SENKOUSPANA, 1);
         if(spana <= 0.0) {
            return NO_SIGNAL;
         }
         // 先行スパンB（雲を形成する線の1つ）
         spanb =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_SENKOUSPANB, 1);
         if(spanb <= 0.0) {
            return NO_SIGNAL;
         }

         // 1本前の価格
         close_Shift1 = Close[1];
         if(close_Shift1 <= 0.0) {
            return NO_SIGNAL;
         }
         
/*printf( "[%d]ICHI チェック 先行A=%s 先行B=%s >>> Close=%s" , __LINE__,
             DoubleToStr(spana, global_Digits),
             DoubleToStr(spanb, global_Digits),
             DoubleToStr(close_Shift1, global_Digits)             
             );*/

         // 買い：価格が雲を上昇ブレイクアウトしたとき
         if(NormalizeDouble(close_Shift1, global_Digits) >= NormalizeDouble(spana, global_Digits) 
            && NormalizeDouble(close_Shift1, global_Digits) >= NormalizeDouble(spanb, global_Digits) ) {
            buysellFlag = BUY_SIGNAL;
         }
         else { 
//printf( "[%d]ICHI 方法=3のBUY不成立 1本前の価格=%s  雲1=%s 雲2=%s " , __LINE__, DoubleToStr(close_Shift1, global_Digits), DoubleToStr(spana, global_Digits), DoubleToStr(spanb, global_Digits) );
            buysellFlag = NO_SIGNAL;
         }
      } //      if(ICHIMOKU_METHOD >= 3) 

      // ４．基準線と価格のクロス　　＝ ICHIMOKU_METHOD = 4。ただし、上記１～３も満たすこと。
      // 買い：価格が基準線を上抜け＆基準線が雲を上回るとき
      // 売り：価格が基準線を下抜け＆基準線が雲を下回るとき
      if(ICHIMOKU_METHOD >= 4 && buysellFlag == BUY_SIGNAL) {
         kijun1 =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_KIJUNSEN, 1);      
         if(NormalizeDouble(close_Shift1, global_Digits) >= NormalizeDouble(kijun1, global_Digits) 
            && NormalizeDouble(kijun1, global_Digits) >= NormalizeDouble(spana, global_Digits) 
            && NormalizeDouble(kijun1, global_Digits) >= NormalizeDouble(spanb, global_Digits) ) {
            buysellFlag = BUY_SIGNAL;
         }
         else { 
//printf( "[%d]ICHI 方法=4のBUY不成立-1 1本前の価格=%s  基準線=%s " , __LINE__, DoubleToStr(close_Shift1, global_Digits), DoubleToStr(kijun1, global_Digits) );
//printf( "[%d]ICHI 方法=4のBUY不成立-2 基準線=%s   雲1=%s 雲2=%s " , __LINE__, DoubleToStr(kijun1, global_Digits), DoubleToStr(spana, global_Digits), DoubleToStr(spanb, global_Digits) );
            buysellFlag = NO_SIGNAL;
         }
      } //      if(ICHIMOKU_METHOD >= 4) 

      // ５．雲のねじれ　　　　　　　＝ ICHIMOKU_METHOD = 5。ただし、上記１～４も満たすこと。
      // 買い：先行スパンAが先行スパンBを上回るとき(雲の陽転)
      // 売り：先行スパンAが先行スパンBを下回るとき(雲の陰転)
      if(ICHIMOKU_METHOD >= 5 && buysellFlag == BUY_SIGNAL) {
         if(NormalizeDouble(spana, global_Digits) >= NormalizeDouble(spanb, global_Digits) ) {
            buysellFlag = BUY_SIGNAL;
         }
         else { 
//printf( "[%d]ICHI 方法=5のBUY不成立  雲1=%s 雲2=%s " , __LINE__, DoubleToStr(spana, global_Digits), DoubleToStr(spanb, global_Digits) );
            buysellFlag = NO_SIGNAL;
         }
      } //      if(ICHIMOKU_METHOD >= 5) 
      
   }  // if(MACD1 > Signal1) 



   // 売りシグナル
   // 共通。MACDがデッドクロス後＝MACD < SIGNAL
   else if(NormalizeDouble(MACD1, global_Digits*2) < NormalizeDouble(Signal1, global_Digits*2) ) {
  
      // １．基準線と転換線のクロス　＝ ICHIMOKU_METHOD = 1
      //  買い：転換線が基準線を上抜けたとき
      //  売り：転換線が基準線を下抜けたとき
      if(ICHIMOKU_METHOD >= 1) {
         mTimeFrame  = global_Period;
         mStartShift = 1; 
         lastGC      = INT_VALUE_MIN;
         lastDC      = INT_VALUE_MIN;
         bool flagIchi = getLastIchi_Cross(mTimeFrame, // 入力：移動平均を計算するための時間軸
                                       mStartShift, // 入力：計算開始位置
                                       lastGC,    // 出力：直近のゴールデンクロスが発生したシフト
                                       lastDC     // 出力：直近のデッドクロスが発生したシフト
                                      );
         if(flagIchi == false) {
            printf( "[%d]ICHI GC, DC発見できず lastGC=%d lastDC=%d" , __LINE__, lastGC, lastDC);
            return NO_SIGNAL;
         }
         else if(lastGC > lastDC) { // GCがDCより遠い(GC>DC)の時、売りシグナル仮置き
            buysellFlag = SELL_SIGNAL;
         }
         else {
            buysellFlag = NO_SIGNAL;
         }

/*
         // 転換線
         tenkan1 = iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_TENKANSEN, 1);
         if(tenkan1 <= 0.0) {
            return NO_SIGNAL;
         }
         tenkan2 = iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_TENKANSEN, 2);
         if(tenkan2 <= 0.0) {
            return NO_SIGNAL;
         }

         // 基準線
         // シフト1
         kijun1 =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_KIJUNSEN, 1);
         if(kijun1 <= 0.0) {
            return NO_SIGNAL;
         }
         // シフト2
         kijun2 =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_KIJUNSEN, 2);
         if(kijun2 <= 0.0) {
            return NO_SIGNAL;
         }
      
         // 売り：転換線が基準線を下抜けたとき
         if( (NormalizeDouble(kijun2, global_Digits) <= NormalizeDouble(tenkan2, global_Digits) 
               && NormalizeDouble(kijun1, global_Digits) >= NormalizeDouble(tenkan1, global_Digits) )
            ||
             (NormalizeDouble(kijun2, global_Digits) >= NormalizeDouble(tenkan2, global_Digits) // 20220411転換線2点が共に上回っている時を追加
               && NormalizeDouble(kijun1, global_Digits) >= NormalizeDouble(tenkan1, global_Digits) )
         ) {
            buysellFlag = SELL_SIGNAL;
         } 
         else { 
            buysellFlag = NO_SIGNAL;
         }
*/
      } //      if(ICHIMOKU_METHOD >= 1) 


      // ２．遅行スパンと価格のクロス＝ ICHIMOKU_METHOD = 2。ただし、上記１も満たすこと。
      // 買い：遅行スパンが26本前の価格を上抜けたとき
      // 売り：遅行スパンが26本前の価格を下抜けたとき
      if(ICHIMOKU_METHOD >= 2 && buysellFlag == SELL_SIGNAL) {
         // 遅行スパン シフトは+26することhttps://investment-vmoney.com/archives/4688
         
         chikou = iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_CHIKOUSPAN, 26 + 1);
         if(chikou <= 0.0) {
            return NO_SIGNAL;
         }
         // 26本前の価格
         close_Shift26 = Close[26 + 1];
         if(close_Shift26 <= 0.0) {
            return NO_SIGNAL;
         }

         // 売り：遅行スパンが26本前の価格を下抜けたとき
         if(NormalizeDouble(chikou, global_Digits) <= NormalizeDouble(close_Shift26, global_Digits) ) {
            buysellFlag = SELL_SIGNAL;
         }
         else { 
//printf( "[%d]ICHI 方法=2のSELL不成立 遅行スパン=%s 26本前の価格=%s" , __LINE__, DoubleToStr(chikou, global_Digits), DoubleToStr(close_Shift26, global_Digits) );
            buysellFlag = NO_SIGNAL;
         }
      } //      if(ICHIMOKU_METHOD >= 2) 

      // ３．雲のブレイクアウト　　　＝ ICHIMOKU_METHOD = 3。ただし、上記１、２も満たすこと。
      // 買い：価格が雲を上昇ブレイクアウトしたとき
      // 売り：価格が雲を下降ブレイクアウトしたとき
      if(ICHIMOKU_METHOD >= 3 && buysellFlag == SELL_SIGNAL) {
      
         // 先行スパンA（雲を形成する線の1つ）
         spana =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_SENKOUSPANA, 1);
         if(spana <= 0.0) {
            return NO_SIGNAL;
         }

         // 先行スパンB（雲を形成する線の1つ）
         spanb =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_SENKOUSPANB, 1);
         if(spanb <= 0.0) {
            return NO_SIGNAL;
         }

         // 1本前の価格
         close_Shift1 = Close[1];
         if(close_Shift1 <= 0.0) {
            return NO_SIGNAL;
         }
/*printf( "[%d]ICHI チェック 先行A=%s 先行B=%s >>> Close=%s" , __LINE__,
             DoubleToStr(spana, global_Digits),
             DoubleToStr(spanb, global_Digits),
             DoubleToStr(close_Shift1, global_Digits)             
             );*/

         // 売り：価格が雲を下降ブレイクアウトしたとき
         if(NormalizeDouble(close_Shift1, global_Digits) <= NormalizeDouble(spana, global_Digits) 
            && NormalizeDouble(close_Shift1, global_Digits) <= NormalizeDouble(spanb, global_Digits) ) {
            
            buysellFlag = SELL_SIGNAL;
         }
         else { 
//printf( "[%d]ICHI 方法=3のSELL不成立 1本前の価格=%s  雲1=%s 雲2=%s " , __LINE__, DoubleToStr(close_Shift1, global_Digits), DoubleToStr(spana, global_Digits), DoubleToStr(spanb, global_Digits) );

            buysellFlag = NO_SIGNAL;
         }
      } //      if(ICHIMOKU_METHOD >= 3) 

      // ４．基準線と価格のクロス　　＝ ICHIMOKU_METHOD = 4。ただし、上記１～３も満たすこと。
      // 買い：価格が基準線を上抜け＆基準線が雲を上回るとき
      // 売り：価格が基準線を下抜け＆基準線が雲を下回るとき
      if(ICHIMOKU_METHOD >= 4 && buysellFlag == SELL_SIGNAL) {
         kijun1 =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_KIJUNSEN, 1);      
      
         if(NormalizeDouble(close_Shift1, global_Digits) <= NormalizeDouble(kijun1, global_Digits) 
            && NormalizeDouble(kijun1, global_Digits) <= NormalizeDouble(spana, global_Digits) 
            && NormalizeDouble(kijun1, global_Digits) <= NormalizeDouble(spanb, global_Digits) ) {
            
            buysellFlag = SELL_SIGNAL;
         }
         else { 
            buysellFlag = NO_SIGNAL;
         }
      } //      if(ICHIMOKU_METHOD >= 4) 

      // ５．雲のねじれ　　　　　　　＝ ICHIMOKU_METHOD = 5。ただし、上記１～４も満たすこと。
      // 買い：先行スパンAが先行スパンBを上回るとき(雲の陽転)
      // 売り：先行スパンAが先行スパンBを下回るとき(雲の陰転)
      if(ICHIMOKU_METHOD >= 5 && buysellFlag == BUY_SIGNAL) {
         if(NormalizeDouble(spana, global_Digits) <= NormalizeDouble(spanb, global_Digits) ) {
            buysellFlag = SELL_SIGNAL;
         }
         else { 
            buysellFlag = NO_SIGNAL;
         }
      } //      if(ICHIMOKU_METHOD >= 5) 
   }  // if(MACD1 > Signal1) 
   return buysellFlag;
} 



// 引数startShift以前の直近の一目均衡表のゴールデンクロス（転換線が基準線の下から上へ抜ける）と
// デッドクロス（転換線が基準線の下から上へ抜ける）を探す。
// 発見したゴールデンクロス発生時点のシフトとデッドクロス発生時点のシフトを引数lastGCとlastDCに代入する。
// 計算中に不具合が発生すれば、falseを返す。その際、引数lastGCとlastDCは-1。それ以外は、trueを返す。
// 多くのトレーダーが使用しているのは、5,25,75 という3種類です。→25MAと75MAを使う。
bool getLastIchi_Cross(int mTimeFrame, // 入力：移動平均を計算するための時間軸
                       int mStartShift, // 入力：計算開始位置
                       int &lastGC,    // 出力：直近のゴールデンクロスが発生したシフト
                       int &lastDC     // 出力：直近のデッドクロスが発生したシフト
                     ){
   int max_shift = 500;  // max_shiftのシフト数だけ、GC, DCを探す。見つからなかったら、-1をセットする。
   if(mStartShift < 0) {
      lastGC = INT_VALUE_MIN;
      lastDC = INT_VALUE_MIN;
      return false;
   }
   
   int mICHIMOKU_Tenkan =  9; //転換線期間
   int mICHIMOKU_Kijun  = 26; //基準線期間
   int mICHIMOKU_Senko  = 52; //先行スパン期間
   
   int i = 0;
   lastGC = INT_VALUE_MIN;
   lastDC = INT_VALUE_MIN;
   double mTenkan1 = 0.0; // 転換線のより最近の(シフト数が小さい）値
   double mTenkan2 = 0.0; // 転換線のより過去の(シフト数が大きい）値
   double mKijun1 = 0.0;  // 基準線のより最近の(シフト数が小さい）値
   double mKijun2 = 0.0;  // 基準線のより過去の(シフト数が大きい）値
   
   for(i = mStartShift; i < mStartShift + max_shift;i++) {
      // ゴールデンクロス（転換線が基準線の下から上へ抜ける）が見つかっていなければ、ゴールデンクロスが発生したかを判定する
      if(lastGC < 0) {
 
         // まず、注目しているシフトの基準線　<= 転換線が成立すること。
         mTenkan1 = iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_TENKANSEN, i);
         mKijun1 =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_KIJUNSEN,  i);

         if(NormalizeDouble(mKijun1, global_Digits) <= NormalizeDouble(mTenkan1, global_Digits) 
            && NormalizeDouble(mKijun1, global_Digits) > 0.0) {
            // さらに、注目しているシフトの１つ過去で基準線　> 転換線が成立すること。
            mTenkan2 = iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_TENKANSEN, i + 1);
            mKijun2 =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_KIJUNSEN,  i + 1);
                          
            if(NormalizeDouble(mKijun2, global_Digits) > NormalizeDouble(mTenkan2, global_Digits) 
               && NormalizeDouble(mTenkan2, global_Digits) > 0.0) {
               lastGC = i - mStartShift;
            }
         }
      } // ゴールデンクロス探索は、ここまで。
      // デッドクロス（転換線が基準線の下から上へ抜ける）が見つかっていなければ、デッドクロスが発生したかを判定する。
      if(lastDC < 0) {
         // まず、注目しているシフトの基準線　>= 転換線が成立すること。
         mTenkan1 = iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_TENKANSEN, i);
         mKijun1 =  iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_KIJUNSEN,  i);
 
         if(NormalizeDouble(mKijun1, global_Digits)  > NormalizeDouble(mTenkan1, global_Digits) 
            && NormalizeDouble(mTenkan1, global_Digits) > 0.0) {
            // さらに、注目しているシフトの１つ過去で基準線　< 転換線が成立すること。
            mTenkan2 = iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_TENKANSEN, i + 1);
            mKijun2  = iIchimoku(global_Symbol, 0, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_KIJUNSEN,  i + 1);

            if(NormalizeDouble(mKijun2, global_Digits)  < NormalizeDouble(mTenkan2, global_Digits) 
               && NormalizeDouble(mKijun2, global_Digits) > 0.0) {
// printf( "[%dCOMM MAデッドクロス発生%s" , __LINE__ , TimeToStr(iTime(global_Symbol,0,i),TIME_DATE | TIME_MINUTES));
            
               lastDC = i - mStartShift;
            }
         }
      } // デッドクロス探索は、ここまで。
      
      if(lastGC >= 0 && lastDC >= 0) {
         //　ゴールデンクロスとデッドクロス両方見つかったので、処理を中断
         break;
      }
   } // for(i = startShift; i < startShift + max_shift;i++)
   
   return true;
}


