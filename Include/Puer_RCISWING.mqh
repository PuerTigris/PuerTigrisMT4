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
int    RCISWING_LEN           = 3;    // 2以上9以下。トレンドを判定する時に何本の足を見るか。最大でも9＝短期線(RCI9)の期間数。
int    RCISWING_SWINGLEG      = 6;    // 6以上。スイングハイ・ローを計算する時に何本の足を見るか。通常は、6。
double RCISWING_EXCLUDE_PER   = 15.0; // スイングハイ、スイングローのRCISWING_EXCLUDE_PERパーセントを取引禁止とする。
double RCISWING_RCI_TOO_BUY   = 80.0; // RCIがこの値以上なら買われすぎ＝売りサイン。RCIは、-100～+100。
double RCISWING_RCI_TOO_SELL  = -80.0;// RCIがこの値以下なら売られすぎ＝買いサイン。RCIは、-100～+100。
*/
/*【参考情報】
global_MaxStrong_UP = 4; // とても強い上昇。3本とも上向き
global_MedStrong_UP = 3; // 強い上昇。　　2本上向き。短期線[9] ↑。中期線[26] ↑。長期線[52] ↓。
global_MinStrong_UP = 2; // やや強い上昇。2本上向き。短期線[9] ↑。中期線[26] ↓。長期線[52] ↑。
global_Weak_UP      = 1; // 弱い上昇。　　2本上向き。短期線[9] ↓。中期線[26] ↑。長期線[52] ↑。
global_MaxStrong_DOWN = -4; // とても強い下落。3本とも下向き
global_MedStrong_DOWN = -3; // 強い下落。　　2本下向き。短期線[9] ↓。中期線[26] ↓。長期線[52] ↑。
global_MinStrong_DOWN = -2; // やや強い下落。2本下向き。短期線[9] ↓。中期線[26] ↑。長期線[52] ↓。
global_Weak_DOWN      = -1; // 弱い下落。　　2本下向き。短期線[9] ↑。中期線[26] ↓。長期線[52] ↓。
global_NO_UPDOWN    = 0; // 判断がつかない場合。:
*/
/*
int    RCISWING_TRENDLEVEL_UPPER  = 1;  // 1～4。-4までは可能。とても強い上昇、強い上昇などのどのレベル以上なら良しとするか。
int    RCISWING_TRENDLEVEL_DOWNER = -1; // -1～-4。4までは可能。とても強い下落、強い下落などのどのレベル以下ら良しとするか。
*/
//+------------------------------------------------------------------+
//|21.RCISWING             　　　　   　　　　　                      |
//+------------------------------------------------------------------+

int entryRCISWINGHighLow() {
// [参考]https://eapapa.com/newrci3-guide/
// RCI3本手法：RCI9,26,52
// 相場の方向：EMA25,50,75,100
//             EMAのパーフェクトオーダーでトレンド確認
// 相場の壁：スイングハイ・ロー。相場の壁（レジスタンスやサポート）での不用意なエントリーを避けるために使う
//           壁の突破（ブレイク）からトレンドを判断する。
//           
// エントリーポイント①：RCI3本の方向が上向きに揃ったら、ロングエントリー。下向きならショートエントリー。
// エントリーポイント②：RCI3本が全て上限に達したら、少し待ち、RCI9が反転後再上昇したところでロングエントリー。
//                       RCI3本が全て下限に達したら、少し待ち、RCI9が反転後再下落したところでショートエントリー。
// 利確ポイント         :目標値達成で利益確定か、トレンドの終了で利益確定。
//                       トレンドの終了とは、
//                         ショートの場合はRCI9が底から上昇し-80を超える時、
//                         ロングの場合はRCI9が天井から下落し80を下回る時
// 損切ポイント　　　　：壁を少し超えたところにセット
                         
   int mSignal = NO_SIGNAL;
   int mTrendFlag = NoTrend; 
   bool mFlag = false;   

   if(RCISWING_LEN > 9 || RCISWING_LEN < 2) {
      return NO_SIGNAL;
   }
   if(RCISWING_EXCLUDE_PER > 100.0 || RCISWING_EXCLUDE_PER <= 0.0) {
      return NO_SIGNAL;
   }

   // RCI3本手法：RCI9,26,52で売買シグナルを計算
   mSignal = judgeRCI3Method(RCISWING_LEN);
   
   if(mSignal == NO_SIGNAL) {
      return NO_SIGNAL;
   } 


   // （売りor買いシグナルの時のみ）EMAのパーフェクトオーダーでトレンド確認
   // 返り値は、UpTrend, DownTrend, NoTrendのいずれか。
   mTrendFlag = get_Trend_PerfectOrder(mSignal, PERIOD_H1, 1);  // シフト＝１の足でトレンドが発生しているかを判断。
   /*
if(mTrendFlag == DownTrend) {
printf( "[%d]RCISWING PerfectOrderは、下落傾向", __LINE__);
}
else if(mTrendFlag == UpTrend) {
printf( "[%d]RCISWING PerfectOrderは、上昇傾向", __LINE__);
}
else{
printf( "[%d]RCISWING PerfectOrderは、傾向無し", __LINE__);
}
*/
   //下落トレンドを確認してショート→厳しすぎるため、上昇傾向でないことを確認してショート継続
   if(mSignal == SELL_SIGNAL && mTrendFlag != UpTrend) {
      mSignal = SELL_SIGNAL;
   }
   //上昇トレンドを確認してロング→厳しすぎるため、下降傾向でないことを確認してロング継続
   else if(mSignal == BUY_SIGNAL && mTrendFlag != DownTrend) {
      mSignal = BUY_SIGNAL;
   }
   else {
      mSignal = NO_SIGNAL;
   }
   if(mSignal == NO_SIGNAL) {
      return NO_SIGNAL;
   } 


   // （売りor買いシグナルの時のみ）スイングハイとスイングローを計算し、突破していることを確認する。
   double mSwingHigh = 0.0;
   double mSwingLow  = 0.0;
   bool   mSwingHLflag = false;

   // getSwingHIGH_LOW(&mSwingHigh, &mSwingLow)は問題が無ければTrueを返し、mSwingHighとmSwingLowに
   // 直近のスイングハイとスイングローをセットする。
   mSwingHLflag = getSwingHIGH_LOW(mSwingHigh, mSwingLow);
   if(mSwingHLflag == true) {
      double mMarketinfoMODE_ASK = MarketInfo(global_Symbol,MODE_ASK);
      double mMarketinfoMODE_BID = MarketInfo(global_Symbol,MODE_BID);

      // RCISWING_EXCLUDE_PERは、スイングハイ、スイングローのRCISWING_EXCLUDE_PERパーセントを取引禁止とする。
      mSwingHigh = NormalizeDouble(mSwingHigh, global_Digits);
      mSwingLow  = NormalizeDouble(mSwingLow, global_Digits);      
      double mSwingDiffUpper = mSwingHigh - NormalizeDouble((mSwingHigh - mSwingLow) * RCISWING_EXCLUDE_PER / 100, global_Digits);
      double mSwingDiffLower = mSwingLow  + NormalizeDouble((mSwingHigh - mSwingLow) * RCISWING_EXCLUDE_PER / 100, global_Digits);
      double mSwingDiffUpperOutside = mSwingHigh + NormalizeDouble((mSwingHigh - mSwingLow) * RCISWING_EXCLUDE_PER / 100, global_Digits);
      double mSwingDiffLowerOutside = mSwingLow  - NormalizeDouble((mSwingHigh - mSwingLow) * RCISWING_EXCLUDE_PER / 100, global_Digits);

      // ASKがスイングハイを上回っていたら壁を越えているのでロング
      // 条件を緩和：スイングハイ・ロー付近の禁止域以外ならロング可能。
      if(mSignal == BUY_SIGNAL 
         && (mMarketinfoMODE_ASK >= mSwingHigh 
            || (mMarketinfoMODE_ASK < mSwingDiffUpper  && mMarketinfoMODE_ASK > mSwingDiffLower )
            ||  (mMarketinfoMODE_ASK > mSwingDiffUpperOutside || mMarketinfoMODE_ASK < mSwingDiffLowerOutside)  ) ){
/*            
printf( "[%d]RCISWING スイングハイとスイングローを使った評価で買いを維持 ASK=%s", __LINE__, DoubleToStr(mMarketinfoMODE_ASK, global_Digits));
printf( "[%d]RCISWING スイングハイとスイングローを使った評価で買いを維持 mSwingDiffUpper=%s mSwingDiffLower=%s", __LINE__, DoubleToStr(mSwingDiffUpper, global_Digits), DoubleToStr(mSwingDiffLower, global_Digits));
printf( "[%d]RCISWING スイングハイとスイングローを使った評価で買いを維持 mSwingDiffUpperOutside=%s mSwingDiffLowerOutside=%s", __LINE__, DoubleToStr(mSwingDiffUpperOutside, global_Digits), DoubleToStr(mSwingDiffLowerOutside, global_Digits));
*/            
         mSignal = BUY_SIGNAL;
      }
      // BIDがスイングローを下回っていたら壁を越えているのでショート
      // 条件を緩和：スイングハイ・ロー付近の禁止域以外ならショート可能。
      else if(mSignal == SELL_SIGNAL
         && (mMarketinfoMODE_BID <= mSwingLow
             || (mMarketinfoMODE_BID < mSwingDiffUpper  && mMarketinfoMODE_BID > mSwingDiffLower ) 
             || (mMarketinfoMODE_BID > mSwingDiffUpperOutside || mMarketinfoMODE_BID < mSwingDiffLowerOutside)  )) {
/*             
printf( "[%d]RCISWING スイングハイとスイングローを使った評価で売りを維持 BID=%s", __LINE__, DoubleToStr(mMarketinfoMODE_BID, global_Digits));
printf( "[%d]RCISWING スイングハイとスイングローを使った評価で売りを維持 mSwingDiffUpper=%s mSwingDiffLower=%s", __LINE__, DoubleToStr(mSwingDiffUpper, global_Digits), DoubleToStr(mSwingDiffLower, global_Digits));
printf( "[%d]RCISWING スイングハイとスイングローを使った評価で売りを維持 mSwingDiffUpperOutside=%s mSwingDiffLowerOutside=%s", __LINE__, DoubleToStr(mSwingDiffUpperOutside, global_Digits), DoubleToStr(mSwingDiffLowerOutside, global_Digits));
*/             
         mSignal = SELL_SIGNAL;
      }
      else {

//printf( "[%d]RCISWING スイングハイ・ロー付近の禁止域のため、売りも買いもシグナル消滅", __LINE__);

         mSignal = NO_SIGNAL;
      }
   }
   else {
//printf( "[%d]RCISWING スイングハイとスイングロー計算エラー", __LINE__);
   
      mSignal = NO_SIGNAL;
   }


   // 発注プロセスを削除。   
   
   return mSignal;
}


// スイングハイ・ローを計算し、引数にセットする。
// スイングハイ…最高値より低い高値のローソク足が、最高値を中心に左右6本できる
// スイングロー…最安値より高い安値のローソク足が、最安値を中心に左右6本できる
// 入力：無し。引数は、計算結果を設定するための変数。
// 出力：正常終了時にTrueを返し、mSwingHighとmSwingLowに直近のスイングハイとスイングローをセットする。
bool getSwingHIGH_LOW(double &mSwingHigh, double &mSwingLow) {
   int swingLength = RCISWING_SWINGLEG;
   int mShift = 0;
   bool retFlag = false;
   double bufCand = 0.0;
   int bufIndex = 0;
      
   mSwingHigh = 0.0;
   mSwingLow  = 0.0;
   
   for(mShift = swingLength; mShift <= 1000; mShift++) {
      if(mSwingHigh <= 0.0) {

         // 注目している足がスイングハイかどうか。
         bufCand = iHigh(global_Symbol, 0, mShift);
         
         if(bufCand > 0.0) {
            bufIndex = iHighest(global_Symbol, 0, MODE_HIGH, swingLength, mShift - swingLength);
            
            if(bufCand >= iHigh(global_Symbol, 0, bufIndex)) {
               bufIndex = 0;
               bufIndex = iHighest(global_Symbol, 0, MODE_HIGH, swingLength, mShift + 1);
               
               if(bufCand >= iHigh(global_Symbol, 0, bufIndex)) {
                  mSwingHigh = bufCand;
               }
            }
         }
         else {
            printf( "[%d]エラー　最大値取得ミス＝%s", __LINE__, TimeToStr(iTime(global_Symbol, 0, mShift)));
         
         }
      }
      if(mSwingLow <= 0.0) {
         bufIndex = 0;
         // 注目している足がスイングローかどうか。
         bufCand = iLow(global_Symbol, 0, mShift);
         if(bufCand > 0.0) {
            bufIndex = iLowest(global_Symbol, 0, MODE_LOW, swingLength, mShift - swingLength);
            if(bufCand <= iLow(global_Symbol, 0, bufIndex)) {
               bufIndex = 0;
               bufIndex =  iLowest(global_Symbol, 0, MODE_LOW, swingLength, mShift + 1);
               if(bufCand <= iLow(global_Symbol, 0, bufIndex)) {
                  mSwingLow = bufCand;
               }
            }
         }
      }
      
      // 直近のスイングハイ、ローが見つかれば、forを中断
      if(mSwingHigh > 0.0 && mSwingLow > 0.0) {
         break;
      }
   }
   
   // 直近のスイングハイ、ローが見つかれば、forを中断
   if(mSwingHigh > 0.0 && mSwingLow > 0.0) {
      retFlag = true;
   }
   else {
      printf( "[%d]エラー スイングハイ・ロー計算失敗　ハイ=%s  ロー=%s" , __LINE__, DoubleToStr(mSwingHigh), DoubleToStr(mSwingLow) );
   }
   return retFlag;
}


//
// judgeRCI3Method用のグローバル変数
//
// RCIを使ったトレンドの強さ判断。
int global_MaxStrong_UP = 4; // とても強い上昇。3本とも上向き
int global_MedStrong_UP = 3; // 強い上昇。　　2本上向き。短期線[9] ↑。中期線[26] ↑。長期線[52] ↓。
int global_MinStrong_UP = 2; // やや強い上昇。2本上向き。短期線[9] ↑。中期線[26] ↓。長期線[52] ↑。
int global_Weak_UP      = 1; // 弱い上昇。　　2本上向き。短期線[9] ↓。中期線[26] ↑。長期線[52] ↑。
int global_MaxStrong_DOWN = -4; // とても強い下落。3本とも下向き
int global_MedStrong_DOWN = -3; // 強い下落。　　2本下向き。短期線[9] ↓。中期線[26] ↓。長期線[52] ↑。
int global_MinStrong_DOWN = -2; // やや強い下落。2本下向き。短期線[9] ↓。中期線[26] ↑。長期線[52] ↓。
int global_Weak_DOWN      = -1; // 弱い下落。　　2本下向き。短期線[9] ↑。中期線[26] ↓。長期線[52] ↓。
int global_NO_UPDOWN    = 0; // 判断がつかない場合。


// 張り付きとみなす本数。
//   これらの数字の本数のRCI[9]が、売られすぎライン、買われすぎラインを超えていたら、張り付きとみなす。
int stay_HIGH = 3; // 最大でも9
int stay_LOW  = 3; // 最大でも9


double mRCI_RCISWING(int timeframe, // 時間軸
                     int len,  // シフト何本分からRCIを計算するか 
                     int shift // シフト何本先からRCIを計算するか
) {
//return mRCI3(timeframe, len, shift);
return mRCI2(global_Symbol, timeframe, len, shift);
}

// RCI3本を使った売買サインを返す
// 短期線[9] :主にエントリーに使用
// 中期線[26]:主にトレンド判断用。
//            +80以上に張り付いてしまったら、１つ上の時間足の短期線・中期線を見る。
//            中期線だけを見ると+80以上に張り付いていると買われすぎのため、売りに見える。
//            しかし、1つ上の時間足で短期線・中期線が上昇中であれば強い上昇のため、売りを控える。
// 長期線[52]:主に上位足のトレンド確認用。
//            こちらもRCI[26]同様に「張り付き」が起こりやすいので、張り付いた場合は上位足を確認する。
// 入力：RCIの動きをmBarCount本前まで確認する。mBarCountは、2以上9以下。
// 出力：BUY_SIGNAL, SELL_SIGNAL, NO_SIGNAL
int judgeRCI3Method(int mBarCount) {

   // 「mBarCountは、2以上9以下。」の条件を満たしていなければ、NO_SIGNALを返す。
   if(mBarCount < 2 || mBarCount > 10) {
      return NO_SIGNAL;
   }

   // 処理の効率化を考え、先に相場の過熱感を見るためにRCIの『位置』を見る。
   // そのあとで、RCIを使ったトレンドの強さ判断をする。
   int buysellFlag = NO_SIGNAL;

   // 相場の過熱感を見るためにRCIの『位置』を見る
   // 一般的に+80を超えると買われすぎ。-80を下回ると売られすぎ。
   //    （売りシグナルの場合で、）短期線[9]の直近値が買われすぎ線RCISWING_RCI_TOO_BUY以上なら、売りシグナル継続。それ以外は、NO_SIGNAL
   //    （買いシグナルの場合で、）短期線[9]の直近値が売られすぎ線RCISWING_RCI_TOO_SELL以上なら、買いシグナル継続。それ以外は、NO_SIGNAL
   
   double mRCI_9_1 =0.0;
   mRCI_9_1 = mRCI_RCISWING(0, // 時間軸 
                            9, // 何本のシフトでRCIを計算するか
                            1);// 何本目のシフトからRCIを計算するか。
/*
printf( "[%d]RCISWING RCI9=%s  %s以上なら売り。%s以下なら買い" , __LINE__, 
             DoubleToStr(NormalizeDouble(mRCI_9_1, global_Digits), global_Digits),
             DoubleToStr(NormalizeDouble(RCISWING_RCI_TOO_BUY,  global_Digits), global_Digits),
             DoubleToStr(NormalizeDouble(RCISWING_RCI_TOO_SELL, global_Digits), global_Digits)
);
*/
   
   if(NormalizeDouble(mRCI_9_1, global_Digits) >= NormalizeDouble(RCISWING_RCI_TOO_BUY, global_Digits)) {
      buysellFlag = SELL_SIGNAL;  // 売りシグナルを設定 
   }
   else if(NormalizeDouble(mRCI_9_1, global_Digits) <= NormalizeDouble(RCISWING_RCI_TOO_SELL, global_Digits)) {
      buysellFlag = BUY_SIGNAL;  // 買いシグナルを設定
   }
   else {
      buysellFlag = NO_SIGNAL;  // RCIの位置が買いでも売りでもないため、NO_SIGNAL
   }
   // この時点でNO_SIGNALまたは、直近RCI9が異常値（100より大か-100未満）ならば、NO_SIGNALを返す
   if(buysellFlag == NO_SIGNAL || (mRCI_9_1 > 100.0 || mRCI_9_1 < -100.0) ) {
      return NO_SIGNAL;
   }


   // RCIを使ったトレンドの強さ判断。
   // - 特に、強い上昇や強い下落の3本の方向が揃ったときにはトレードチャンス
   //   mUpDownが、global_MedStrong_UP(3)以上、または、global_MedStrong_DOWN(-3)以下。
   // - トレンドの強さは、getTrend_RCI(mBarCount)で、mBarCountまでさかのぼってRCIを計算し直線回帰により上昇か下落を判断する。
   // 　　返り値は、global_MaxStrong_UP = 4～global_MaxStrong_DOWN = -4まで。
   int mUpDown = global_NO_UPDOWN;
   
   if(buysellFlag != NO_SIGNAL) {
      mUpDown = getTrend_RCI(mBarCount);
string strBuf =get_TrendName(mUpDown);
//printf( "[%d]RCISWING buysellFlag(BUY=1)=>%d<  getTrend_RCIで勢い判定結果=%s = %d", __LINE__, buysellFlag, strBuf, mUpDown);
      
  
      // 強い上昇ならば、買いシグナル
//      if(buysellFlag == BUY_SIGNAL && mUpDown >= global_MedStrong_UP) {       
      if(buysellFlag == BUY_SIGNAL && mUpDown >= RCISWING_TRENDLEVEL_UPPER) {       
         RCISWING_TRENDLEVEL_UPPER = BUY_SIGNAL;
      }
//      else if(buysellFlag == SELL_SIGNAL && mUpDown <= global_MedStrong_DOWN) {
      else if(buysellFlag == SELL_SIGNAL && mUpDown <= RCISWING_TRENDLEVEL_DOWNER) {
         buysellFlag = SELL_SIGNAL;
      }
      else {      
         buysellFlag = NO_SIGNAL;
      }
   }
/*   
if(buysellFlag == BUY_SIGNAL) {
printf( "[%d]RCISWING 勢いも考えて買い判定", __LINE__);
}
else if(buysellFlag == SELL_SIGNAL) {
printf( "[%d]RCISWING 勢いも考えて判定", __LINE__);
}   
else {
printf( "[%d]RCISWING 勢いを考えると、シグナル消滅", __LINE__);
}
*/
   // この時点でNO_SIGNAならば、NO_SIGNALを返す
   if(buysellFlag == NO_SIGNAL) {
      return NO_SIGNAL;
   }

   int i;
   bool mStayflag = false;  // 張り付いていたらtrue。
   double mRCI_26 = 0.0;
   double bufRCI4Regression[100];
   int    bufRCI4Regression_size = 0;
   int tf1UP = PERIOD_CURRENT; // 張り付き時に使う、1つ上の時間足。ENUM_TIMEFRAMESとする。PERIOD_CURRENTは、初期値であり、後で更新する。
   int tfNow = Period();       // 張り付き時に使う、現在の時間軸。
   double slope_9 = 0.0;      // 張り付き時に使う、短期線[9]の1つ上の時間足の傾き。
   double slope_26 = 0.0;     // 張り付き時に使う、中期線[26]の1つ上の時間足の傾き。
   double intercept_9 = 0.0;  // 張り付き時に使う、短期線[9]の1つ上の時間足の切片。
   double intercept_26 = 0.0; // 張り付き時に使う、中期線[26]の1つ上の時間足の切片。     
   int ii = 0;
   bool flagRCI_slope ;

   if(buysellFlag == SELL_SIGNAL) {   
   // 売りシグナルの場合で、
   //    買われすぎ線RCISWING_RCI_TOO_BUYに張り付き（中期線[26]が、過去int stay_HIGH本に渡ってRCISWING_RCI_TOO_BUY以上）の場合は、
   //    １つ上の時間足の短期線[9]・中期線[26]が共に上昇中であれば売りを控える
      mStayflag = false;   
      for(i = 1; i <= stay_HIGH; i++) {
         mRCI_26 = mRCI_RCISWING(0, 26, i);         
         if(mRCI_26 < RCISWING_RCI_TOO_BUY) {
            mStayflag = false; //　張り付きではなくなった。
            break;
         }
         else {
            mStayflag = true; // 張り付き中
         }
      }
      
      
      // 過去int stay_HIGH本に渡ってRCISWING_RCI_TOO_BUY以上ならば、
      // １つ上の時間足の短期線[9]・中期線[26]が共に上昇中であれば売りを控える
      if(mStayflag == true) {  
         // 中期線[26]が張り付いているとみなされたので、１つ上の時間足が上昇中であれば、SELLを取りやめる
         // １つ上の時間軸を入手する。
         // ただし、現在の時間足が最大のPERIOD_MN1の場合は、1つ上はないため、そのまま。
         tf1UP = PERIOD_CURRENT; // 1つ上の時間足。ENUM_TIMEFRAMESとする。PERIOD_CURRENTは、初期値であり、後で更新する。
         tfNow = Period();
         if(tfNow == PERIOD_MN1) {
            tf1UP = PERIOD_MN1;
         }
         else {
            tf1UP = getTimeFrameReverse(tfNow);  // 現在のENUM_TIMEFRAMES型の時間足を0～9に変換
            tf1UP = tf1UP + 1;  // 変換した値に1を加えて、1つ上の時間足を意味する。
            tf1UP = getTimeFrame(tf1UP); // 0～9にした時間足を、ENUM_TIMEFRAMES型に変換する。
         }
         
         ii = 0;
         // 短期線[9]の傾きを調べる。
         for(ii = 0; ii < mBarCount; ii++) {
            bufRCI4Regression[ii] = mRCI_RCISWING(tf1UP,  // 時間軸 
                                                  9,      // 何本のシフトでRCIを計算するか
                                                  ii + 1);    // 何本目のシフトからRCIを計算するか。
         }
         bufRCI4Regression_size = mBarCount;
         flagRCI_slope = calcRegressionLine(bufRCI4Regression, bufRCI4Regression_size, slope_9, intercept_9);
         slope_9 = slope_9 * (-1.0);
         // 「１つ上の時間足の短期線[9]・中期線[26]が共に上昇中であれば売りを控える売りを控える」のため、
         // 短期線[9]が上昇中以外であれば、中期線[26]の傾きは計算しない。
         if(flagRCI_slope == false || slope_9 <= 0.0) {
         }
         else {  // 短期線[9]が上昇中のため、中期線[26]の傾きを計算する。
            ArrayInitialize(bufRCI4Regression, 0);
            for(ii = 0; ii < mBarCount; ii++) {
               bufRCI4Regression[ii] = mRCI_RCISWING(tf1UP, 26, ii);
            }
            bufRCI4Regression_size = mBarCount;
            flagRCI_slope = calcRegressionLine(bufRCI4Regression, bufRCI4Regression_size, slope_26, intercept_26);
            slope_26 = slope_26 * (-1);
            

            //１つ上の時間足の短期線[9]・中期線[26]が共に上昇中であれば売りを控える
            if(flagRCI_slope == false || slope_26 > 0.0) {
               buysellFlag = NO_SIGNAL; 
            }
            else {
            }
         }
      }
      else {
      }
   }
   else if(buysellFlag == BUY_SIGNAL) {
   // 買いシグナルの場合で、
   //    売られすぎ線RCISWING_RCI_TOO_SELLに張り付き（中期線[26]が、過去int stay_LOW本に渡ってRCISWING_RCI_TOO_SELL以下）の場合は、
   //    １つ上の時間足の短期線[9]・中期線[26]が共に下降中であれば買いを控える
      mStayflag = false;   
      for(i = 1; i <= stay_LOW; i++) {
         mRCI_26 = mRCI_RCISWING(0, 26, i);
         if(mRCI_26 > RCISWING_RCI_TOO_SELL) {
            mStayflag = false; //　RCISWING_RCI_TOO_SELLをうわまわったことで、張り付きではなくなった。
            break;
         }
         else {
            mStayflag = true; // 張り付き中
         }
      }
      
      
      // 過去int stay_Low本に渡ってRCISWING_RCI_TOO_SELL以下ならば、
      // １つ上の時間足の短期線[9]・中期線[26]が共に下落中であれば買いを控える
      if(mStayflag == true) {  
      
         // 中期線[26]が張り付いているとみなされたので、１つ上の時間足が下落中であれば、BUYを取りやめる
         // １つ上の時間軸を入手する。
         // ただし、現在の時間足が最大のPERIOD_MN1の場合は、1つ上はないため、そのまま。
         tf1UP = PERIOD_CURRENT; // 1つ上の時間足。ENUM_TIMEFRAMESとする。PERIOD_CURRENTは、初期値であり、後で更新する。
         tfNow = Period();
         if(tfNow == PERIOD_MN1) {
            tf1UP = PERIOD_MN1;
         }
         else {
            tf1UP = getTimeFrameReverse(tfNow);  // 現在のENUM_TIMEFRAMES型の時間足を0～9に変換
            tf1UP = tf1UP + 1;  // 変換した値に1を加えて、1つ上の時間足を意味する。
            tf1UP = getTimeFrame(tf1UP); // 0～9にした時間足を、ENUM_TIMEFRAMES型に変換する。
         }
         
         ii = 0;
         // 短期線[9]の傾きを調べる。
         ArrayInitialize(bufRCI4Regression, 0.0);
         for(ii = 0; ii < mBarCount; ii++) {
            bufRCI4Regression[ii] = mRCI_RCISWING(tf1UP, 9, ii);
/*printf( "[%d]RCISWING 下で張り付き中のRCI9の傾き計算用　　シフト=%d  RCI=%s" , __LINE__, 
             ii, DoubleToStr(bufRCI4Regression[ii], global_Digits));*/
         }
         bufRCI4Regression_size = mBarCount;
         flagRCI_slope = calcRegressionLine(bufRCI4Regression, bufRCI4Regression_size, slope_9, intercept_9);
         slope_9 = slope_9 * (-1.0);  
         
/*
printf( "[%d]RCISWING RCI9の傾き計算結果（－１倍前）　　傾き=%s  切片=%s" , __LINE__, 
          DoubleToStr(slope_9, global_Digits),
          DoubleToStr(intercept_9, global_Digits)
);*/

         // 「１つ上の時間足の短期線[9]・中期線[26]が共に下落中であれば買いを控える」のため、
         // 短期線[9]が下落以外であれば、中期線[26]の傾きは計算しない。
         if(flagRCI_slope == false || slope_9 >= 0.0) {
         }
         else {  // 短期線[]が下落中のため、中期線[26]の傾きを計算する。
         
            ArrayInitialize(bufRCI4Regression, 0);
            for(ii = 0; ii < mBarCount; ii++) {
               bufRCI4Regression[ii] = mRCI_RCISWING(tf1UP, 26, ii);
/*               
printf( "[%d]RCISWING RCI26の傾き計算用　　シフト=%d  RCI=%s" , __LINE__, 
             ii, DoubleToStr(bufRCI4Regression[ii], global_Digits));*/

            }
            bufRCI4Regression_size = mBarCount;
            flagRCI_slope = calcRegressionLine(bufRCI4Regression, bufRCI4Regression_size, slope_26, intercept_26);
            slope_26 = slope_26 * (-1.0);              
            
            //１つ上の時間足の短期線[9]・中期線[26]が共に上昇中であれば売りを控える売りを控える
            if(flagRCI_slope == false || slope_26 < 0.0) {
               buysellFlag = NO_SIGNAL; 
            }
            else {
            }
         } 
      }
      else {
      }
      
   }

   return buysellFlag;
}

// mBarCount本をさかのぼって、RCI3本の方向を計算し、トレンドの強さを返す。
/*
   int global_MaxStrong_UP = 4; // とても強い上昇。3本とも上向き
   int global_MedStrong_UP = 3; // 強い上昇。　　2本上向き。短期線[9] ↑。中期線[26] ↑。長期線[52] ↓。
   int global_MinStrong_UP = 2; // やや強い上昇。2本上向き。短期線[9] ↑。中期線[26] ↓。長期線[52] ↑。
   int global_Weak_UP      = 1; // 弱い上昇。　　2本上向き。短期線[9] ↓。中期線[26] ↑。長期線[52] ↑。
   int global_MaxStrong_DOWN = -4; // とても強い下落。3本とも下向き
   int global_MedStrong_DOWN = -3; // 強い下落。　　2本下向き。短期線[9] ↓。中期線[26] ↓。長期線[52] ↑。
   int global_MinStrong_DOWN = -2; // やや強い下落。2本下向き。短期線[9] ↓。中期線[26] ↑。長期線[52] ↓。
   int global_Weak_DOWN      = -1; // 弱い下落。　　2本下向き。短期線[9] ↑。中期線[26] ↓。長期線[52] ↓。
   int global_NO_UPDOWN    = 0; // 判断がつかない場合。
*/
int getTrend_RCI(int mBarCount) {
   int ret = global_NO_UPDOWN;
   
   if(mBarCount > 9) {   // mBarCountは、最大でも、RCI（９）の9まで。
      mBarCount = 9;
   }
   if(mBarCount < 1) {   // mBarCountは、最小で1まで。
      mBarCount = 1;
   }
  
   int RCI09_UPDOWN = analyzeRCI( 9,          // 何本のシフトでRCIを計算するか
                                  mBarCount); // 何本目のシフトから計算したRCIを傾きの計算に使うか。
   int RCI26_UPDOWN = analyzeRCI(26,          // 何本のシフトでRCIを計算するか
                                 mBarCount);  // 何本目のシフトから計算したRCIを傾きの計算に使うか。
   int RCI52_UPDOWN = analyzeRCI(52,          // 何本のシフトでRCIを計算するか
                                 mBarCount);  // 何本目のシフトから計算したRCIを傾きの計算に使うか。


   // 上昇の4段階判定
   if(RCI09_UPDOWN == UpTrend && RCI26_UPDOWN == UpTrend && RCI52_UPDOWN == UpTrend) {
      ret = global_MaxStrong_UP;
   }
   else if(RCI09_UPDOWN == UpTrend && RCI26_UPDOWN == UpTrend && RCI52_UPDOWN == DownTrend) {
      ret = global_MedStrong_UP;
   }
   else if(RCI09_UPDOWN == UpTrend && RCI26_UPDOWN == DownTrend && RCI52_UPDOWN == UpTrend) {
      ret = global_MinStrong_UP;
   }   
   else if(RCI09_UPDOWN == DownTrend && RCI26_UPDOWN == UpTrend && RCI52_UPDOWN == UpTrend) {
      ret = global_Weak_UP;
   }    
   // 下落の4段階判定
   else if(RCI09_UPDOWN == DownTrend && RCI26_UPDOWN == DownTrend && RCI52_UPDOWN == DownTrend) {
      ret = global_MaxStrong_DOWN;
   }   
   else if(RCI09_UPDOWN == DownTrend && RCI26_UPDOWN == DownTrend && RCI52_UPDOWN == UpTrend) {
      ret = global_MedStrong_DOWN;
   }     
   else if(RCI09_UPDOWN == DownTrend && RCI26_UPDOWN == UpTrend && RCI52_UPDOWN == DownTrend) {
      ret = global_MinStrong_DOWN;
   }     
   else if(RCI09_UPDOWN == UpTrend && RCI26_UPDOWN == DownTrend && RCI52_UPDOWN == DownTrend) {
      ret = global_Weak_DOWN;
   }
   // 該当なし
   else {
      printf( "[%d]RCISWING 4段階判定該当なし。短期=%d  中期=%d  長期=%d", __LINE__, RCI09_UPDOWN, RCI26_UPDOWN, RCI52_UPDOWN);

      ret = global_NO_UPDOWN;
   }
   
 
   return ret;
}
/*   
int analyzeRCI(int mLength,   // 何本のシフトでRCIを計算するか
               int mBarCount  // 何本目のシフトから計算したRCIを傾きの計算に使うか。
   ) {
   int RCI09_UPDOWN = analyzeRCI( 9,          // 何本のシフトでRCIを計算するか
                                  mBarCount); // 何本目のシフトから計算したRCIを傾きの計算に使うか。
   int RCI26_UPDOWN = analyzeRCI(26,          // 何本のシフトでRCIを計算するか
                                 mBarCount);  // 何本目のシフトから計算したRCIを傾きの計算に使うか。
   int RCI52_UPDOWN = analyzeRCI(52,          // 何本のシフトでRCIを計算するか
                                 mBarCount);  // 何本目のシフトから計算したRCIを傾きの計算に使うか。



   // 上昇の4段階判定
   if(RCI09_UPDOWN == UpTrend && RCI26_UPDOWN == UpTrend && RCI52_UPDOWN == UpTrend) {
      ret = global_MaxStrong_UP;
   }
   else if(RCI09_UPDOWN == UpTrend && RCI26_UPDOWN == UpTrend && RCI52_UPDOWN == DownTrend) {
      ret = global_MedStrong_UP;
   }
   else if(RCI09_UPDOWN == UpTrend && RCI26_UPDOWN == DownTrend && RCI52_UPDOWN == UpTrend) {
      ret = global_MinStrong_UP;
   }   
   else if(RCI09_UPDOWN == DownTrend && RCI26_UPDOWN == UpTrend && RCI52_UPDOWN == UpTrend) {
      ret = global_Weak_UP;
   }    
   // 下落の4段階判定
   else if(RCI09_UPDOWN == DownTrend && RCI26_UPDOWN == DownTrend && RCI52_UPDOWN == DownTrend) {
      ret = global_MaxStrong_DOWN;
   }   
   else if(RCI09_UPDOWN == DownTrend && RCI26_UPDOWN == DownTrend && RCI52_UPDOWN == UpTrend) {
      ret = global_MedStrong_DOWN;
   }     
   else if(RCI09_UPDOWN == DownTrend && RCI26_UPDOWN == UpTrend && RCI52_UPDOWN == DownTrend) {
      ret = global_MinStrong_DOWN;
   }     
   else if(RCI09_UPDOWN == UpTrend && RCI26_UPDOWN == DownTrend && RCI52_UPDOWN == DownTrend) {
      ret = global_Weak_DOWN;
   }
   // 該当なし
   else {
      printf( "[%d]RCISWING 4段階判定該当なし。短期=%d  中期=%d  長期=%d", __LINE__, RCI09_UPDOWN, RCI26_UPDOWN, RCI52_UPDOWN);

      ret = global_NO_UPDOWN;
   }
   
 
   return ret;
}
*/

// 引数mPeriodは、RCIを計算する期間。短期線なら9,中期線なら26、長期線なら52
int analyzeRCI(int mLength,   // 何本のシフトでRCIを計算するか
               int mBarCount  // 何本目のシフトから計算したRCIを傾きの計算に使うか。
   ) {
   int i;
   int retUpDown = global_NO_UPDOWN;
   double RCI_value[9999];
   
   if(mLength < mBarCount) {
      return NoTrend;
   }
   for(i = 1; i <= mBarCount; i++) {
      RCI_value[i - 1] = mRCI_RCISWING(0,      // 時間軸 
                                       mLength,// 何本のシフトでRCIを計算するか
                                       i);     // 何本目のシフトからRCIを計算するか。
//printf( "[%d]RCISWING　analyzeRCIで傾き計算　シフト%d--RCI＝%s", __LINE__, i, DoubleToStr(RCI_value[i - 1], global_Digits));
      
   }
   bool flag = false;
   double mSlope = 0.0;
   double mIntercept = 0.0;
   flag = calcRegressionLine(RCI_value, mBarCount, mSlope, mIntercept);
/*printf( "[%d]RCISWING　analyzeRCIで傾き計算(mSlopeを-1倍する前)　傾き=%s   切片=%s", __LINE__,
           DoubleToStr(mSlope, global_Digits),
           DoubleToStr(mIntercept, global_Digits)
);*/

   // calcRegressionLineが成功した時は、傾きでUP/DOWNを判定。
   if(flag == true) {
      mSlope = mSlope * (-1.0);
      if(mSlope >= 0.0) {  // 傾き0.0は、上昇とみなす。
//printf( "[%d]RCISWING　時刻=%s  slope＝%sであり、上昇中", __LINE__, TimeToStr(Time[0]), DoubleToStr(mSlope, global_Digits));
      
         retUpDown = UpTrend;
      }
      else {
//printf( "[%d]RCISWING　時刻=%s  slope＝%sであり、下落中", __LINE__, TimeToStr(Time[0]), DoubleToStr(mSlope, global_Digits));

         retUpDown = DownTrend;
      }
   }
   else {
      retUpDown = NoTrend;
   }
   
   return retUpDown;
}





// getTrend_RCIで取得した勢い（int型）を文字列に変換する。
string get_TrendName(int mUpDown) {
   string buf;
   if(mUpDown == global_MaxStrong_UP) {
      buf = "とても強い上昇";
   }
   else if(mUpDown == global_MedStrong_UP) {
      buf = "強い上昇";
   }
   else if(mUpDown == global_MinStrong_UP) {
      buf = "やや強い上昇";
   }
   else if(mUpDown == global_Weak_UP) {
      buf = "弱い上昇";
   }
   else if(mUpDown == global_NO_UPDOWN) {
      buf = "判断がつかない";
   }
   else if(mUpDown == global_MaxStrong_DOWN) {
      buf = "とても強い下落";
   }
   else if(mUpDown == global_MedStrong_DOWN) {
      buf = "強い下落";
   }
   else if(mUpDown == global_MinStrong_DOWN) {
      buf = "やや強い下落";
   }
   else if(mUpDown == global_Weak_DOWN) {
      buf = "弱い下落";
   }
   else {
      buf = "例外発生！！";
   }   
   
   return buf;
}