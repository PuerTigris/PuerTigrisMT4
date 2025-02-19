//+------------------------------------------------------------------+
//|  統計的手法関連部品                                                |
//|  Copyright (c) 2016 トラの親 All rights reserved.                |
//|                                                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| ヘッダーファイル読込                                             |
//+------------------------------------------------------------------+
#include <Tigris_COMMON.mqh>
#include <Tigris_GLOBALS.mqh>
//#include <Puer_STAT.mqh>  // 偏差や平均を計算する関数calcMeanAndSigmaを使うため。

//+------------------------------------------------------------------+
//| 定数宣言部                                                       |
//+------------------------------------------------------------------+
#define MAX_CLASS_NUM 1000 // 最頻値を求める際の階級の最大数

#define MAX_MRA_EXP_DATA_NUM 400 // 重回帰分析をする際の対象データ数最大
#define MAX_MRA_DEGREE 100           // 重回帰分析をする際の次数最大
#define MIN_DEGREE 2             // 重回帰分析をする際の次数最小

//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+
//| グローバル変数宣言                                                     |
//+------------------------------------------------------------------+
struct st_class {  // 最頻値を求める際の階級（start, end)と度数
   double start;   // 区間（クラス）の始め。この値以上を区間とする
   double end;     // 区間（クラス）の終わり。この値未満を区間とする。最大値を含むため、最大値+1*glopal_Pointsとする。
   int    dataNum; // 区間に該当するデータの件数
   bool   mode;    // trueの時最頻値。最大のdataNumを持つ区間のため、配列内の複数の要素でtrueとなる可能性あり。
};

int TYPE_OPEN  = 1; // 重回帰分析対象データをOpen値とする。
int TYPE_HIGH  = 2; // 重回帰分析対象データをHigh値とする。
int TYPE_LOW   = 3; // 重回帰分析対象データをLow値とする。
int TYPE_CLOSE = 4; // 重回帰分析対象データをClose値とする。
int TYPE_MA5_MA25    = 5; // 重回帰分析対象データをMACDとSIGNALの差とする。
int TYPE_MACD_SIG    = 6; // 重回帰分析対象データをMACDとSIGNALの差とする。
int TYPE_BBUP_BBDOWN = 7; // 重回帰分析対象データをBBの上と下の差とする。
int TYPE_SLOPEH4     = 8; // 重回帰分析対象データを4時間足の傾きとする。
int TYPE_RSI         = 9; // 重回帰分析対象データをRSIの値とする。
int TYPE_DMI         = 10; // 重回帰分析対象データを±DIの差とする。
//+------------------------------------------------------------------+
//| 統計関連の関数　                                                     |
//+------------------------------------------------------------------+
//
// 1次元データの平均と標準偏差（σ）を計算する。
//
// 分散と標準偏差 = https://yorikuwa.com/m1504/
// データ   偏差   偏差の２乗
// x1     x1−m	(x1−m)2
// x2	    x2−m	(x2−m)2
// x3	    x3−m	(x3−m)2
// ・・・
// xn	    xn−m	(xn−m)2
// mは平均。
// 分散は、（分散）＝（偏差の２乗の和）÷（データの合計個数）
// 標準偏差は、分散に平方根を付けたもの
bool calcMeanAndSigma(double &mData[], int mDataNum, double &mMean, double &mSigma) {

   mMean  = 0.0;
   mSigma = 0.0;
   
   int i;
   int bufNum = 0;
   // 平均を求める
   // ※念のため、データmData[]にdouble型最小値が入っていないことを検証する。
   for(i = 0; i < mDataNum; i++) {
      if(NormalizeDouble(mData[i], global_Digits) > DOUBLE_VALUE_MIN) {
      
         mMean = NormalizeDouble(mMean, global_Digits) + NormalizeDouble(mData[i], global_Digits);
         
         bufNum++;
      }
   } 
   if(bufNum < 1) {
      mMean  = DOUBLE_VALUE_MIN;
      mSigma = DOUBLE_VALUE_MIN;
printf( "[%d]STATエラー　データ数が1未満" , __LINE__);
      
      return false;
   }
   else {
      mDataNum = bufNum;  // データmData[]にdouble型最小値が入っていた場合に、件数を更新する。
   }
   mMean = NormalizeDouble(mMean / mDataNum, global_Digits);
   
   // 分散を求める。
   // 偏差の２乗の和
   for(i = 0; i < mDataNum; i++) {
      mSigma = mSigma + (NormalizeDouble(mData[i], global_Digits) - NormalizeDouble(mMean, global_Digits)) * (NormalizeDouble(mData[i], global_Digits) - NormalizeDouble(mMean, global_Digits));
   } 
   // （偏差の２乗の和）÷（データの合計個数）=分散
   mSigma = NormalizeDouble(mSigma / mDataNum, global_Digits*2);  // 小数点以下global_Digits桁の2乗のため、global_Digits*2の精度で計算する・
   mSigma = NormalizeDouble(MathSqrt(mSigma), global_Digits);

   return true;
}

//
// 2次元データ（度数分布表）の平均と標準偏差（σ）を計算する。
//
//  分散は、各データに対して「平均値との差」（＝偏差）の二乗値を計算し、
//  その総和をデータ数で割った値（＝平均値）を表す。 標準偏差（σ）は、分散に対する平方根の値を表す。
// 度数分布表と分散 = https://yorikuwa.com/m1505/2/
// 1 階級値と階級値×度数を求める。
//    以上〜未満   階級値   度数   階級値×度数
//    0 〜 10      5        2      5×2=10
//    10 〜 20     15       7      15×7=105
//    20 〜 30     25       12     25×12=300
//    30 〜 40     35       15     35×15=525
//    40 〜 50     45       4      45×4=180
// 2 階級値×度数の合計を求める。 10+105+300+525+180=1120
// 3 平均値は、(階級値×度数の合計)÷データ数。ただし、データ数はデータの総数であり、階級の数ではないので注意。1120÷40=28
// 4 度数×(階級値の２乗)の合計を求める。
//    階級値   度数   階級値の２乗   度数×階級値の２乗
//    5        2      25             50
//    15       7      225            1575
//    25       12     625            7500
//    35       15     1225           18375
//    45       4      2025           8100
// 度数×階級値の２乗の合計は、50+1575+7500+18375+8100 =35600
// 5 度数×(階級値の２乗)の平均値を求める。{度数×(階級値の２乗)の合計}÷データ数。ただし、データ数はデータの総数であり、階級の数ではないので注意。
// 6 分散は、度数×(階級値の２乗)の平均値 - 平均値の2乗
// 7 標準偏差（σ）は、分散の平方根

// 引数：mData[][] = 計算対象の度数分布表mData[i][0]=階級値, mData[i][1]=度数
//       mDataNum  = データ数。mData[0][]～mData[mDataNum - 1][]
//       mMean     = 計算した平均値
//       mSigma    = 計算した分散
// 返り値:計算成功時にtrue、失敗時はfalse。
bool calcMeanAndSigma(double &mData[][], int mDataNum, double &mMean, double &mSigma) {
   if(mDataNum < 1) {
      return false;
   }
   double num = 0.0;
   double sumRankNum = 0.0;
   double sumRankNumPOW2 = 0.0;
   double mean1 = 0.0;
   double mean2 = 0.0;
   // 1 階級値と階級値×度数を求める。
   // 2 階級値×度数の合計を求める。 10+105+300+525+180=1120
   // 4 度数×(階級値の２乗)の合計を求める。度数×(階級値の２乗)を合計する。
   for(int i = 0; i < mDataNum; i++) {
      // mData[i][0]=階級値, mData[i][0]=度数
//printf( "[%d]テスト　階級値=%s  度数=%s" , __LINE__, DoubleToStr(mData[i][0]), DoubleToStr(mData[i][1]));   
      num = num + mData[i][1];
      mean1 = NormalizeDouble(mean1, global_Digits)  + NormalizeDouble(mData[i][0], global_Digits)  * NormalizeDouble(mData[i][1], global_Digits) ;
      mean2 = NormalizeDouble(mean2, global_Digits)  + NormalizeDouble(mData[i][0], global_Digits)  * NormalizeDouble(mData[i][0] * mData[i][1], global_Digits) ;
   }

   // 3 平均値は、(階級値×度数の合計)÷データ数。ただし、データ数はデータの総数であり、階級の数ではないので注意。1120÷40=28
//printf( "[%d]テスト　階級値×度数の合計=%s  度数×(階級値の２乗)の合計=%s  データ数=%d" , __LINE__, DoubleToStr(mean1), DoubleToStr(mean2), num);   
   if(num > 0.0) {
      mean1 = NormalizeDouble(mean1, global_Digits) / num;
   }
   else {
      return false;
   }
   mMean = mean1;
   
   // 5 度数×(階級値の２乗)の平均値を求める。{度数×(階級値の２乗)の合計}÷データ数。ただし、データ数はデータの総数であり、階級の数ではないので注意。
   mean2 = NormalizeDouble(mean2, global_Digits)  / num;

   // 6 分散は、度数×(階級値の２乗)の平均 - 平均値の2乗
   // 7 標準偏差（σ）は、分散の平方根
   mSigma = MathSqrt(NormalizeDouble(mean2, global_Digits)  - NormalizeDouble(mean1, global_Digits) * NormalizeDouble(mean1, global_Digits) );

/*
 int fileHandle2 = FileOpen("occur.csv", FILE_WRITE | FILE_CSV ,",");
  if(fileHandle2 != INVALID_HANDLE){
   //省略
   for(i = 0; i < mDataNum; i++) {      
      FileWrite(fileHandle2 , 
         i,
         mData[i][0], mData[i][1]);
   }
   FileWrite(fileHandle2 , "mean1", mean1);
   FileWrite(fileHandle2 , "mean2", mean2);
   FileWrite(fileHandle2 , "Sigma", mSigma);
 }
 else {
   printf( "[%d]ファイルオープンエラー：PoplationTable_rows" , __LINE__);
   Print(GetLastError());
 }    
 FileClose(fileHandle2);
*/    
   return true;
}


// 引数mComparedが、mMean±mConst*mSigmaの範囲内にあれば、trueを返す。
// mCompared、mMean、mSigmaのいずれかがDOUBLE_VALUE_MINの時は、trueを返す。
bool judgeInclude(double mMean, double mSigma, double mConst, double mCompared, string mComment) {

   if(mMean == DOUBLE_VALUE_MIN
      || mSigma == DOUBLE_VALUE_MIN
      || mCompared == DOUBLE_VALUE_MIN) {

      return true;
   }
   else {
      bool compareFlag = false;
      if(NormalizeDouble(mCompared, global_Digits) >=  NormalizeDouble(mMean, global_Digits) - NormalizeDouble(mConst, global_Digits) * NormalizeDouble(mSigma, global_Digits)) {
         if(NormalizeDouble(mCompared, global_Digits) <=  NormalizeDouble(mMean, global_Digits) + NormalizeDouble(mConst, global_Digits) * NormalizeDouble(mSigma, global_Digits)) {
            compareFlag =  true;
         }
      }
      if(compareFlag == false) {
         return false;
      }
      else {
         /// 範囲内にあるため、次の項目へ。
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| 最頻値を計算する。  
//| 第1引数：最頻値を求める母集団の配列
//| 第2引数：母集団をいくつの区間にわけるか。
//| 第3引数：出力：第1引数で渡した配列の値を、第2引数で渡した数の階級に分け、
//|        各クラスの件数及び最頻値を計算した結果。                              |
//+------------------------------------------------------------------+
bool calc_Mode(double  &mDiffArray[],      //　最頻値を求める母集団の配列
               int      mClassNum,         // 階級(class)の数
               st_class &m_st_classArray[] // 出力：第1引数で渡した配列の値を、第2引数で渡した数の階級に分け、各クラスの件数及び最頻値を計算する。
            ) {
   if(mClassNum < 1) {
      return false;
   }

   int i;
   // 配列の初期化
   init_st_class(m_st_classArray);

   //
   // データ件数、最大値、最小値を求める。
   //
   // 差額が入っている配列を降順でソートする。
   ArraySort(mDiffArray, WHOLE_ARRAY, 0, MODE_DESCEND);  

   // 差額が入っている配列の最大項目数を取得する。
   int mSize = ArraySize(mDiffArray);

   // 母集団を区間数mClassNumに分割するため、最大値と最小値を計算する。
   double priceDiff_Max = DOUBLE_VALUE_MIN;
   double priceDiff_Min = DOUBLE_VALUE_MAX;
   int    priceDiff_dataNum = 0;
   for(i = 0; i < mSize; i++) {  

      // 配列mDiffArrayは、降順にソート済みのため、最初にDOUBLE_VALUE_MINが登場したら、処理を中断する。
      if(NormalizeDouble(mDiffArray[i], global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)) {
         break;
      }

      // 最大
      if(NormalizeDouble(priceDiff_Max, global_Digits) <= NormalizeDouble(mDiffArray[i], global_Digits)) {
/*printf( "[%d]STAT 最大を更新　priceDiff_Max=%s →　%s" , __LINE__,
         DoubleToStr(priceDiff_Max, global_Digits),
         DoubleToStr(mDiffArray[i], global_Digits)
         );*/
         
         priceDiff_Max = NormalizeDouble(mDiffArray[i], global_Digits);


      }
      // 最小
      else if(NormalizeDouble(priceDiff_Min, global_Digits) > NormalizeDouble(mDiffArray[i], global_Digits)) {

/*printf( "[%d]STAT 最小を更新　priceDiff_Min=%s →　%s" , __LINE__,
            DoubleToStr(priceDiff_Min, global_Digits),
            DoubleToStr(mDiffArray[i], global_Digits)
            );*/
      
         priceDiff_Min = NormalizeDouble(mDiffArray[i], global_Digits);
      }
      priceDiff_dataNum++;
   }

/*printf( "[%d]STAT 最大値=%s 最小値=%s 求めるのに確認した差額データ件数=%d" , __LINE__,
          DoubleToStr(priceDiff_Max, global_Digits),
          DoubleToStr(priceDiff_Min, global_Digits),
          priceDiff_dataNum
       );*/
   if(priceDiff_dataNum <= 0
      || priceDiff_Min == DOUBLE_VALUE_MAX
      || priceDiff_Max == DOUBLE_VALUE_MIN
      ) {
printf( "[%d]STAT 最大値, 最小値を取得できず" , __LINE__);
      return false;
   }
   
   // 母集団double  &mDiffArray[]を
   // 最大値から最小値の間を階級の数mClassNumにわける
   double classWidth = NormalizeDouble((NormalizeDouble(priceDiff_Max, global_Digits) - NormalizeDouble(priceDiff_Min, global_Digits)) / (double)mClassNum, global_Digits*2);
//printf( "[%d]STAT 階級の幅classWidth=%s" , __LINE__, DoubleToStr(classWidth, global_Digits));
   
   for(i = 0; i < mClassNum; i++) {
      m_st_classArray[i].start = NormalizeDouble(priceDiff_Min, global_Digits) + NormalizeDouble(classWidth * (double)i, global_Digits);
      m_st_classArray[i].end   = NormalizeDouble(priceDiff_Min, global_Digits) + NormalizeDouble(classWidth * (double)(i + 1), global_Digits);      
   } 
   // 階級(class)を、start以上end未満としていることから、最後の階級のendを最大値とすると、最大値をカウントできない。
   // 階級分けした際の誤差もありうるため、m_st_classArrayの最後のendは、最大値 + 5.0 * global_Pointsで上書きする。
/*printf( "[%d]STAT %d番目の階級=m_st_classArray[%d]  end=%s を %sに変更" , __LINE__,
mClassNum,
mClassNum-1,
DoubleToStr(m_st_classArray[mClassNum - 1].end, global_Digits),
DoubleToStr(NormalizeDouble(NormalizeDouble(priceDiff_Max, global_Digits) + 0.01, global_Digits), global_Digits) );
*/
   m_st_classArray[mClassNum - 1].end = NormalizeDouble( (NormalizeDouble(priceDiff_Max, global_Digits) + 1*global_Points), global_Digits);
   // 件数dataNumのDOUBLE_VALUE_MINを0にする。
   for(i = 0; i < mClassNum; i++) {
      if(m_st_classArray[i].dataNum == INT_VALUE_MIN) {
         m_st_classArray[i].dataNum = 0;
      }
   } 
/*
printf( "[%d]STAT 最小=%s   最大=%s 　区間の先頭[0]=%s  区間の最後[%d]=%s" , __LINE__,
DoubleToStr(priceDiff_Min, global_Digits),
DoubleToStr(priceDiff_Max, global_Digits),
DoubleToStr(m_st_classArray[0].start, global_Digits),
mClassNum -1,
DoubleToStr(m_st_classArray[mClassNum-1].end, global_Digits)
);

for(i = 0; i < mClassNum; i++) {
printf( "[%d]STAT 階級=start, end =%s,%s" , __LINE__,
DoubleToStr(m_st_classArray[i].start, global_Digits),
DoubleToStr(m_st_classArray[i].end, global_Digits)
);
} 
*/    
 
   // mDiffArrayの値を階級m_st_classArrayに割り振る
   int j;
   for(i = 0; i < mSize; i++) {  // mSizeは、差額の配列mDiffArrayの最大項目数
      if(NormalizeDouble(mDiffArray[i], global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)) {
         break;
      }
      for(j = 0; j < mClassNum; j++) {
         if(NormalizeDouble(m_st_classArray[j].start, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)) {
            break;
         }
         
         if( (NormalizeDouble(m_st_classArray[j].start, global_Digits) <= NormalizeDouble(mDiffArray[i], global_Digits)) 
               &&
             (NormalizeDouble(m_st_classArray[j].end, global_Digits) > NormalizeDouble(mDiffArray[i], global_Digits))
            ) {
            if(m_st_classArray[j].dataNum < 0){
               m_st_classArray[j].dataNum = 1;
            }
            else {
               m_st_classArray[j].dataNum++;
            }
         }
      }
   }   


   // 最頻値を求める。
   // ①m_st_classArray[j].dataNumの最大値modeNumを求め、
   // ②m_st_classArray[j].dataNum = modeNumを満たす全ての要素で、m_st_classArray[j].dataNumをtrueとする。
   // ①の処理
   int modeNum = INT_VALUE_MIN; // 階級別度数の最大値が入る
   for(i = 0; i < mClassNum; i++) {
      if( (m_st_classArray[i].dataNum >= 0)
          &&
          (modeNum < m_st_classArray[i].dataNum) ) {
         modeNum = m_st_classArray[i].dataNum;
      } 
   } 
   
   // ②の処理
   for(i = 0; i < mClassNum; i++) {
      if( (m_st_classArray[i].dataNum >= 0.0)
          &&
          (modeNum == m_st_classArray[i].dataNum ) ) {
         m_st_classArray[i].mode = true;
      }
      else {
         m_st_classArray[i].mode = false;
      }
   } 
/*
   // データ確認用
   for(i = 0; i < mSize; i++) {
      if(NormalizeDouble(mDiffArray[i], global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)) {
         break;
      }
printf( "[%d]STAT クラス分けする基データ %s" , __LINE__, DoubleToStr(mDiffArray[i], global_Digits));
   }
   for(i = 0; i < MAX_CLASS_NUM; i++) {
      if(NormalizeDouble(m_st_classArray[i].start, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)) {
         break;
      }
string buf = "";
if(m_st_classArray[i].mode == true) {
   buf = "最頻値";
}
else {
   buf = "---";
}
printf( "[%d]STAT i=%d クラス別データ件数 >%s<～>%s< >%d<件 最頻値かどうか=>%s<" , __LINE__, i, 
         DoubleToStr(m_st_classArray[i].start, global_Digits), 
         DoubleToStr(m_st_classArray[i].end, global_Digits),          
         m_st_classArray[i].dataNum, 
         buf
       );
   }   
   // データ確認用ここまで
*/
   
//   double mPriceDiff_Mode = NormalizeDouble(0.5*(NormalizeDouble(m_st_classArray[i].start, global_Digits*2) + NormalizeDouble(m_st_classArray[i].end, global_Digits*2)), global_Digits);
   return true;
}  

void init_st_class(st_class &m_st_classArray[]) {
   int i;
   for(i = 0; i < MAX_CLASS_NUM; i++) {
      m_st_classArray[i].start   = DOUBLE_VALUE_MIN;
      m_st_classArray[i].end     = DOUBLE_VALUE_MIN;
      m_st_classArray[i].dataNum = INT_VALUE_MIN;
      m_st_classArray[i].mode    = false;
   }
}

bool get_NearToMeanMode(st_class &m_st_classArray[], // 最頻値の入った構造体
                        double   m_Mean, // 平均値。この値に最も近い最頻値を探す。
                        double   &m_nearToMeanMode  // 出力：最頻値の代表値
                        ) {
   int i;
   double classValue = DOUBLE_VALUE_MIN;
   double distanceFromMean_MIN = DOUBLE_VALUE_MAX;
   for(i = 0; i < MAX_CLASS_NUM; i++) {
      if(NormalizeDouble(m_st_classArray[i].start, global_Digits) == NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)) {
         break;
      }
      if(m_st_classArray[i].mode == true) {
         // 階級の幅を計算する。絶対値に変換。
         classValue = MathAbs(NormalizeDouble(m_st_classArray[i].start, global_Digits) - NormalizeDouble(m_st_classArray[i].end, global_Digits));
         // 階級の代表値を、start + 階級の幅の絶対値÷2とする。
         classValue = NormalizeDouble(NormalizeDouble(m_st_classArray[i].start, global_Digits) + classValue / 2.0, global_Digits);
/*printf( "[%d]STAT クラス別データ件数が最大のクラスは、>%s<～>%s<で、>%d<件 最頻値の代表値=>%s<" , __LINE__,
         DoubleToStr(m_st_classArray[i].start, global_Digits), 
         DoubleToStr(m_st_classArray[i].end, global_Digits),          
         m_st_classArray[i].dataNum,
         DoubleToStr(classValue, global_Digits)); */

      
         // 平均値と階級の代表値の距離が最小であれば、返り値である最頻値m_nearToMeanModeを更新する。
         if( NormalizeDouble(distanceFromMean_MIN, global_Digits) >= MathAbs(NormalizeDouble(m_Mean, global_Digits) - NormalizeDouble(classValue, global_Digits)) ) {
            distanceFromMean_MIN = MathAbs(NormalizeDouble(m_Mean, global_Digits) - NormalizeDouble(classValue, global_Digits));
            m_nearToMeanMode = NormalizeDouble(classValue, global_Digits);
         }
      }
   }
/*printf( "[%d]STAT 最頻値の代表値のうち、平均値=>%s<に一番近いのは>%s<" , __LINE__,
         DoubleToStr(m_Mean, global_Digits), 
         DoubleToStr(m_nearToMeanMode, global_Digits)         
      ); */
      

   if(classValue == DOUBLE_VALUE_MIN || m_nearToMeanMode == DOUBLE_VALUE_MIN) {
      return false;
   }
   else {
      return true;
   }
   
   return true;
}


//
//
// 重回帰分析関連
//
//
//
// 重回帰分析に使用する説明変数（degree列datanum行）のデータを引数exp1にセットする。
// 
void create_ExpMatrix(int    datatype,  // 説明変数に入れるデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                      int    mTimeframe,// 説明変数を取得するデータの時間軸。
                      double &exp1[][], // 出力:説明変数の入る配列四値やRSI、MAなど
                      int    &degree,   // 出力:次数
                      int    &datanum   // 出力:データ件数
                      ) {
   if(degree > MAX_MRA_DEGREE) {
      return ;
   } 
   
 
   int i;
   int j;
   
   //
   // 説明変数の設定
   //
   // exp1[0][0]=シフト1, exp1[0][1]=シフト2, exp1[0][2]=シフト3, ,,exp1[0][n]=シフトn
   // DATA_NUM件のデータをそろえるためには、exp1[0][0]～exp1[DATA_NUM+DEGREE+1][0]用意し、
   // exp1[1][0]～exp1[1][]は、exp1[0][1]～exp1[DATA_NUM+DEGREE+1][0]をコピーする。
   string symbol = Symbol();

   for(i = 0; i < datanum*2+1; i++) { 
      // 引数datatypeにより、セットするデータを変更する。
      exp1[i][0] = get_EachTypeValue(datatype,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                     mTimeframe,// 取得するデータの時間軸。
                                     i + 1      // 取得するデータのシフト。
                                     );
//printf("[%d]STA データ取得中exp1[0][%d]=%s", __LINE__, i, DoubleToString(exp1[0][i], 8));       
   }

   for(i = 0; i < datanum; i++) {
      for(j = 1; j < degree; j++) {
         exp1[i][j] = exp1[i + j][0];
      }
   }

   MqlDateTime cjtm; // 時間構造体
   TimeToStruct(TimeCurrent(), cjtm); // 構造体の変数に変換
   if(cjtm.hour == 0 && cjtm.min == 0 && cjtm.sec == 0) {
      printf("[%d]STA 説明変数のテスト出力>%s<時点 タイプ=%d ", __LINE__, TimeToString(TimeCurrent()), datatype);       

      for(i = 0; i < datanum; i++) {
         for(j = 0; j < degree; j++) {
            printf("[%d]STA 説明変数exp1[%d][%d]=%s", __LINE__, i, j, DoubleToString(exp1[i][j], 8));       
         }
      }
   }
}



void create_ExpMatrix_VariousData
                     (int    datatype,  // 説明変数に入れるデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                      int    mTimeframe,// 説明変数を取得するデータの時間軸。
                      int    mExp_Matrix_pattern, // 説明変数のデータパターン　1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, slopeH4
                      double &exp1[][], // 出力:説明変数の入る配列四値やRSI、MAなど
                      int    &degree,   // 出力:次数
                      int    &datanum   // 出力:データ件数
                      ) {
   if(degree > MAX_MRA_DEGREE) {
      return ;
   } 
   
 
   int i;
 //  int j;
   
   //
   // 説明変数の設定
   //
   // exp1[0][0]=シフト1, exp1[0][1]=シフト2, exp1[0][2]=シフト3, ,,exp1[0][n]=シフトn
   // DATA_NUM件のデータをそろえるためには、exp1[0][0]～exp1[DATA_NUM+DEGREE+1][0]用意し、
   // exp1[1][0]～exp1[1][]は、exp1[0][1]～exp1[DATA_NUM+DEGREE+1][0]をコピーする。
   string symbol = Symbol();
   //
   // MRA_EXP_TYPE = 1の時
   if(mExp_Matrix_pattern == 1) {
      for(i = 0; i < datanum; i++) { 
         // 1:exp1[i][0]MA5 - MA25, exp1[i][1]MACD-Signal, exp1[i][2]BB_UP - BB_DOWN, exp1[i][3]slopeH4
         // 引数datatypeにより、セットするデータを変更する。
         exp1[i][0] = get_EachTypeValue(TYPE_MA5_MA25,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
               
         exp1[i][1] = get_EachTypeValue(TYPE_MACD_SIG,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][2] = get_EachTypeValue(TYPE_BBUP_BBDOWN,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][3] = get_EachTypeValue(TYPE_SLOPEH4,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
      }
      
      degree = 4;      

   }
   //
   // MRA_EXP_TYPE = 2の時
   else if(mExp_Matrix_pattern == 2) {
      for(i = 0; i < datanum; i++) { 
         // 1:exp1[i][0]MA5 - MA25, exp1[i][1]MACD-Signal, exp1[i][2]BB_UP - BB_DOWN, exp1[i][3]slopeH4
         // 引数datatypeにより、セットするデータを変更する。
         exp1[i][0] = get_EachTypeValue(TYPE_MA5_MA25,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
               
         exp1[i][1] = get_EachTypeValue(TYPE_MACD_SIG,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][2] = get_EachTypeValue(TYPE_BBUP_BBDOWN,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][3] = get_EachTypeValue(TYPE_RSI,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
      }
      degree = 4;      
   }      
   //
   // MRA_EXP_TYPE = 3＝１（SLOPE）＋２（RSI)の時
   else if(mExp_Matrix_pattern == 3) {
      for(i = 0; i < datanum; i++) { 
         // 1:exp1[i][0]MA5 - MA25, exp1[i][1]MACD-Signal, exp1[i][2]BB_UP - BB_DOWN, exp1[i][3]slopeH4
         // 引数datatypeにより、セットするデータを変更する。
         exp1[i][0] = get_EachTypeValue(TYPE_MA5_MA25,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
               
         exp1[i][1] = get_EachTypeValue(TYPE_MACD_SIG,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][2] = get_EachTypeValue(TYPE_BBUP_BBDOWN,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][3] = get_EachTypeValue(TYPE_SLOPEH4,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][4] = get_EachTypeValue(TYPE_RSI,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
      }
      degree = 5;      
   } 
   // MRA_EXP_TYPE = 4の時
   else if(mExp_Matrix_pattern == 4) {
      for(i = 0; i < datanum; i++) { 
         // 1:exp1[i][0]MA5 - MA25, exp1[i][1]MACD-Signal, exp1[i][2]BB_UP - BB_DOWN, exp1[i][3]slopeH4
         // 引数datatypeにより、セットするデータを変更する。
         exp1[i][0] = get_EachTypeValue(TYPE_MA5_MA25,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
               
         exp1[i][1] = get_EachTypeValue(TYPE_MACD_SIG,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][2] = get_EachTypeValue(TYPE_BBUP_BBDOWN,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][3] = get_EachTypeValue(TYPE_DMI,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
      }
      degree = 4;      
   }   
   // MRA_EXP_TYPE = 5＝１（SLOPE）＋4（DI)の時の時
   else if(mExp_Matrix_pattern == 5) {
      for(i = 0; i < datanum; i++) { 
         // 1:exp1[i][0]MA5 - MA25, exp1[i][1]MACD-Signal, exp1[i][2]BB_UP - BB_DOWN, exp1[i][3]slopeH4
         // 引数datatypeにより、セットするデータを変更する。
         exp1[i][0] = get_EachTypeValue(TYPE_MA5_MA25,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
               
         exp1[i][1] = get_EachTypeValue(TYPE_MACD_SIG,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][2] = get_EachTypeValue(TYPE_BBUP_BBDOWN,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][3] = get_EachTypeValue(TYPE_SLOPEH4,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][4] = get_EachTypeValue(TYPE_DMI,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
      }
      degree = 5;      
   }
   // MRA_EXP_TYPE = 6＝2（RSI）＋4（DI)の時の時
   else if(mExp_Matrix_pattern == 6) {
      for(i = 0; i < datanum; i++) { 
         // 1:exp1[i][0]MA5 - MA25, exp1[i][1]MACD-Signal, exp1[i][2]BB_UP - BB_DOWN, exp1[i][3]slopeH4
         // 引数datatypeにより、セットするデータを変更する。
         exp1[i][0] = get_EachTypeValue(TYPE_MA5_MA25,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
               
         exp1[i][1] = get_EachTypeValue(TYPE_MACD_SIG,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][2] = get_EachTypeValue(TYPE_BBUP_BBDOWN,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][3] = get_EachTypeValue(TYPE_RSI,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][4] = get_EachTypeValue(TYPE_DMI,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
      }
      degree = 5;      
   }   
   // MRA_EXP_TYPE = 7＝1(SLOPE) + 2（RSI）＋4（DI)の時の時
   else if(mExp_Matrix_pattern == 7) {
      for(i = 0; i < datanum; i++) { 
         // 1:exp1[i][0]MA5 - MA25, exp1[i][1]MACD-Signal, exp1[i][2]BB_UP - BB_DOWN, exp1[i][3]slopeH4
         // 引数datatypeにより、セットするデータを変更する。
         exp1[i][0] = get_EachTypeValue(TYPE_MA5_MA25,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
               
         exp1[i][1] = get_EachTypeValue(TYPE_MACD_SIG,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][2] = get_EachTypeValue(TYPE_BBUP_BBDOWN,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][3] = get_EachTypeValue(TYPE_SLOPEH4,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][4] = get_EachTypeValue(TYPE_RSI,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
         exp1[i][5] = get_EachTypeValue(TYPE_DMI,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                        mTimeframe,// 取得するデータの時間軸。
                                        i + 1      // 取得するデータのシフト。
                                        );
      }
      degree = 6;      
   }   
   else {
   
      degree = -1;
   }



}


//
// 重回帰分析に使用する目的変数（1列datanum行）のデータを引数resにセットする。
// 
void create_ResMatrix(int    datatype,// 目的変数に入れるデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                      int    mTimeframe,// 説明変数を取得するデータの時間軸。
                      double &res[],  // 出力:目的変数の入る配列
                      int    &datanum // 出力:データ件数
                     ) {
 
   ArrayInitialize(res, 0.0);
   
   int i;
   
   //
   // 目的変数の設定
   // ※説明変数である配列expがシフト１からデータを取得するのに対して、目的変数は、シフト１～ｎに基づいて発生した値のため、シフト０からデータを取得する。
   // res[0]=シフト0, res[1]=シフト1, res[2]=シフト2, ,,res[0][n]=シフトn
   
   string symbol = Symbol();
   for(i = 0; i < datanum; i++) { 
      // 引数datatypeにより、セットするデータを変更する。
      res[i] = get_EachTypeValue(datatype,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                 mTimeframe,// 取得するデータの時間軸。
                                 i      // 取得するデータのシフト。
                                 );
/*
printf("[%d]STA 目的変数[%d], %s, %s", __LINE__, i,
        TimeToString(iTime(symbol, mTimeframe, i + 1)),
        DoubleToString(res[i], 5)
         );*/

   }

   MqlDateTime cjtm; // 時間構造体
   TimeToStruct(TimeCurrent(), cjtm); // 構造体の変数に変換
//   if(cjtm.hour == 0 && cjtm.min == 0 && cjtm.sec == 0) {
//      printf("[%d]STA 目的変数のテスト出力>%s<時点 タイプ=%d ", __LINE__, TimeToString(TimeCurrent()), datatype);       
//
//      for(i = 0; i < datanum; i++) {
//         printf("[%d]STA 目的変数res[%d]=%s", __LINE__, i, DoubleToString(res[i], 8));       
//      }
//   }

}

// 重回帰分析【参考】https://www.ritsumei.ac.jp/se/rv/dse/jukai/MRA.html
// 目的変数 |説明変数
//                i, degree
//    y   | x1    x2    x3 |
//    ----------------------
//    y1  | x11   x12   x13|
// j  y2  | x21   x22   x23|   datanum
//    y3  | x31   x32   x33|
//   　のとき、重回帰式 y = b0 + b1*x1 + b2*x2 + b3*x3を満たすb0, b1, b2, b3は、次のとおり
//    b0 = (yの平均) - b1*(x1の平均) - b2*(x2の平均)  - b3*(x3の平均) 
//    ただし、b1, b2, b3は以下を満たす
//    |S11  S12  S13| |b1|   |Σ(xi1*yi) - n*(x1の平均)*(yの平均)|
//    |S21  S22  S13| |b2| = |Σ(xi2*yi) - n*(x2の平均)*(yの平均)|
//    |S31  S32  S33| |b3|   |Σ(xi3*yi) - n*(x1の平均)*(yの平均)|
//     S11 = Σ(xi1)*(xi1) - n*(x1の平均)^2 = Σ(xi1)^2 - n*(x1の平均)^2
//     S12 = Σ(xi1)*(xi2) - n*(x1の平均)*(x2の平均)
//     S13 = Σ(xi1)*(xi3) - n*(x1の平均)*(x3の平均)
bool calc_Multiple_regression_analysis(double &exp_var[][], // 説明変数
                                       int     degree,      // 説明変数の次数。x1～x3であれば、3
                                       int     datanum,     // 説明変数の個数。100件のデータなど
                                       double &res_var[],   // 目的変数
                                       double &slope[],     // 出力：係数=b1, b2, b3...
                                       double &intercept    // 出力：切片=b0
                                       ) {
   if(degree <= 0 || degree >= MAX_MRA_DEGREE) {
printf("[%d]STA エラー degree = >%d<", __LINE__, degree);      
      return false;
   }
   if(datanum <= 0) {
printf("[%d]STA エラー", __LINE__);       
      return false;
   }
   double mean_x[MAX_MRA_DEGREE];        // (x1の平均)=mean_x[0]、(x2の平均)=mean_x[1]、(x3の平均)=mean_x[3]、、、を格納する。
   double mean_y = DOUBLE_VALUE_MIN; // (yの平均)、を格納する。
   double gaussMatrix1[MAX_MRA_DEGREE][MAX_MRA_DEGREE];
   double gaussMatrix2[MAX_MRA_DEGREE];
   // 初期化
   ArrayInitialize(slope,   DOUBLE_VALUE_MIN);
   ArrayInitialize(mean_x,   DOUBLE_VALUE_MIN);
   ArrayInitialize(gaussMatrix1,   DOUBLE_VALUE_MIN); 
   ArrayInitialize(gaussMatrix2,   DOUBLE_VALUE_MIN);    
   intercept = DOUBLE_VALUE_MIN;
   int i;
   int j;

   // (x1の平均)、(x2の平均)、(x3の平均)、、、を計算する。
   ArrayInitialize(mean_x, 0.0);
   for(i = 0; i < datanum; i++ ) {
      for(j = 0; j < degree; j++) {
         mean_x[j] += exp_var[i][j];
      }
   }
   for(j = 0; j < degree; j++) {
      mean_x[j] = mean_x[j] / datanum;
   }
//   for(i = 0; i < degree; i++ ) {
//     printf("[%d]STA mean_x[%d]=%s", __LINE__, i, DoubleToString(mean_x[i], 20));         
//   }


   mean_y = 0.0;
   for(i = 0; i < datanum; i++ ) {
      mean_y += res_var[i];
//printf("[%d]STA 少数チェック　mean_y=%s", __LINE__, DoubleToString(mean_y, 20));         
      
   }
   mean_y = mean_y  / datanum;
//printf("[%d]STA 少数チェック　mean_y=%s", __LINE__, DoubleToString(mean_y, 20));         
   
   // Sij = Σ(xi*xj) - n*(x1の平均)*(xjの平均)を計算する。
   // 計算結果は、ガウスの消去法を計算するための配列gaussMatrixに入れる。
   // gaussMatrix[0][0] = S11
   int m;
 
   ArrayInitialize(gaussMatrix1, 0.0);
   for(i = 0; i < degree; i++) {
      for(j = 0; j < degree; j++) {
         for(m = 0; m < datanum; m++) {
               gaussMatrix1[i][j] += exp_var[m][i] * exp_var[m][j]; 
         }
      }
   }
   for(i = 0; i < degree; i++) {
      for(j = 0; j < degree; j++) {   
//printf("[%d]STA SijのΣ部分　gaussMatrix1[%d][%d]=%s", __LINE__, i, j, DoubleToString(gaussMatrix1[i][j], 20));         
      }
   }
      

   for(i = 0; i < degree; i++) {
      for(j = 0; j < degree; j++) {   
         gaussMatrix1[i][j] = gaussMatrix1[i][j] - datanum * mean_x[i] * mean_x[j];
      }
   }
   for(i = 0; i < degree; i++) {
      for(j = 0; j < degree; j++) {   
//printf("[%d]STA Sij完成版　gaussMatrix1[%d][%d]=%s", __LINE__, i, j, DoubleToString(gaussMatrix1[i][j], 20));         
      }
   }
   
   // 
   // gaussMatrix2の計算
   //      
   ArrayInitialize(gaussMatrix2, 0.0);
   for(j = 0; j < degree; j++) {
      for(i = 0; i < datanum; i++) {
         gaussMatrix2[j] += exp_var[i][j] * res_var[i]; 
      }
   }
   for(j = 0; j < degree; j++) {
      gaussMatrix2[j] = gaussMatrix2[j] - datanum * mean_x[j] * mean_y;
   }   
   
 
   for(j = 0; j < degree; j++) {
//printf("[%d]STA 少数チェック　gaussMatrix2[%d]=%s", __LINE__, i, DoubleToString(gaussMatrix2[j], 20));   
   }      


   // ガウスの消去法で連立方程式を解く。
   calc_Gauss(gaussMatrix1, // 説明変数。
              gaussMatrix2, // 目的変数
              degree); 

   // 出力用変数に計算結果をコピーする。
   for(i = 0; i < degree; i++) {
      slope[i] = gaussMatrix2[i];     
   }         

   //  切片の計算  
   //    b0 = (yの平均) - b1*(x1の平均) - b2*(x2の平均)  - b3*(x3の平均) 
   intercept = mean_y;
   for(i = 0; i < degree; i++) {
      intercept = intercept - slope[i] * mean_x[i]; 
   }
   
   
   return true;
}


bool calc_Gauss(double &gaussMatrix1[][],
                double &gaussMatrix2[],
                int    degree) {
   int org;
   int change;
   int i;
   double arg = 0.0; // 引かれる行の値÷引く行の値
   for(org = 0; org < degree; org++) {
      for(change = 0; change < degree; change++) {
         if(org == change) {
            continue;
         }
         if(gaussMatrix1[org][org] == 0.0) {
            continue;
         }
         
         arg = gaussMatrix1[change][org] / gaussMatrix1[org][org];
         for(i = 0; i < degree; i++) {
            gaussMatrix1[change][i] = gaussMatrix1[change][i] - gaussMatrix1[org][i] * arg;
         }
         gaussMatrix2[change] = gaussMatrix2[change] - gaussMatrix2[org] * arg;
      }
   }
   for(org = 0; org < degree; org++) {
      for(change = 0; change < degree; change++) {
         if(gaussMatrix1[change][change] == 0.0) {
            continue;
         }
         if(org == change) {
            gaussMatrix2[change] = gaussMatrix2[change] / gaussMatrix1[change][change];
         }
      }
   }
   /*
for(i = 0; i < degree; i++) {
   for(int j = 0; j < degree; j++) {
      printf("[%d]STA 結果gauss1[%d][%d]=%s", __LINE__, i, j, DoubleToString(gaussMatrix1[i][j], 8));   
   }
} 
for(i = 0; i < degree; i++) {
   printf("[%d]STA 結果gauss2[%d]=%s", __LINE__, i, DoubleToString(gaussMatrix2[i], 8));   
} 
*/
return true;
}



// 重回帰分析を使った、直後データの予測
// MRAは、Multiple_regression_analysisの略。
// 重回帰分析により、重回帰式 y = b0 + b1*x1 + b2*x2 + b3*x3 + ・・・　+ bn*xn(ただし、nはMRA_DEGREE）を満たすb0, b1, b2, b3,,,bnを計算し、
// シフト0の値をx1、シフト1の値をx2、、、シフト(n-1)の値をxnに代入して、直後データyを計算する。
//
// 
// ※ 出力が、次の予測値1を返すバージョン
bool calc_NextData_MRA(int    datatype,  // 直近データの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                       int    mTimeframe,// 取得するデータの時間軸。原則として、0=PERIOD_CURRENT
                       int    mDegree,
                       int    mDatanum,    // 予測に使用するデータ件数
                       double &calcData  // 出力：直後のデータ
                       ) {
   // 次数が1以下の時は計算しない。
   if(MAX_MRA_DEGREE <= 1) {
      printf("[%d]JIKKENエラー 重回帰分析用次数MRA_DEGREEE=%dが、1以下", __LINE__, MAX_MRA_DEGREE);   
      return false;
   }
   // データ数が次数＋１以下の時は、計算しない。
   if(MAX_MRA_EXP_DATA_NUM <= MAX_MRA_DEGREE + 1) {
      printf("[%d]JIKKENエラー 重回帰分析用データ数MRA_DATA_NUM=%d が、次数MRA_DEGREEE=%d+1以下", __LINE__, MAX_MRA_EXP_DATA_NUM, MAX_MRA_DEGREE);   
      return false;
   }

   double exp_matrix[MAX_MRA_EXP_DATA_NUM][MAX_MRA_DEGREE];
   double res_matrix[MAX_MRA_EXP_DATA_NUM];
   ArrayInitialize(exp_matrix, DOUBLE_VALUE_MIN);
   ArrayInitialize(res_matrix, DOUBLE_VALUE_MIN);

   create_ExpMatrix(datatype,    // 説明変数に入れるデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                    mTimeframe,  // データ取得に用いる時間軸
                    exp_matrix,  // 出力:説明変数の入るシフト１以降の配列四値やRSI、MAなど。説明変数exp_matrix[0][]は、シフト１のデータ　→　目的変数の先頭データはシフト0のデータ
                    mDegree,     // 出力:次数
                    mDatanum     // 出力:データ件数
                   );
                      
   // 目的変数（1列datanum行）のデータを引数res_matrixにセットする。
   create_ResMatrix(datatype,  // 目的変数に入れるシフト0以降のデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                    mTimeframe,
                    res_matrix, // 出力:目的変数の入る配列四値やRSI、MAなど。res_matrix[0]は、シフト0のデータ　←　説明変数exp_matrix[0][]は、シフト１のデータ
                    mDatanum     // 出力:データ件数                   
                   );


   // 重回帰分析により、slope及びinterceptを計算する。
   double slope[MAX_MRA_EXP_DATA_NUM];
   double intercept;
   calc_Multiple_regression_analysis(exp_matrix, // 説明変数
                                     mDegree,     // 説明変数の次数。x1～x3であれば、3
                                     mDatanum,    // 説明変数の個数。100件のデータなど
                                     res_matrix, // 目的変数
                                     slope,      // 出力：係数=b1, b2, b3...
                                     intercept   // 出力：切片=b0
                                     );   
   int i;
/*   for(i = 0; i < mDegree; i++) {
      printf("[%d]STA 結果slope[%d]=%s", __LINE__, i, DoubleToString(slope[i], 8));   
   }
   printf("[%d]STA 結果intercept=%s", __LINE__, DoubleToString(intercept, 20));
*/
   // 予測データy = b0 + b1*x1 + b2*x2 + b3*x3 + ・・・　+ bn*xnを計算する
   calcData = intercept;
   double Xn = 0.0; // 予測データを計算する際のx1, x2, x3, ,,, xnを代入する。 
   for(i = 0; i < mDegree; i++) {
      Xn = 0.0;
      // 引数datatypeにより、セットするデータを変更する。
      Xn = get_EachTypeValue(datatype,  // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                             mTimeframe,// 取得するデータの時間軸。
                             i      // 取得するデータのシフト。
                             );

      calcData = calcData + slope[i] * Xn;
   }
   
   return true;

}

// 重回帰分析を使った、直後データの予測
// MRAは、Multiple_regression_analysisの略。
// 重回帰分析により、重回帰式 y = b0 + b1*x1 + b2*x2 + b3*x3 + ・・・　+ bn*xn(ただし、nはMRA_DEGREE）を満たすb0, b1, b2, b3,,,bnを計算し、
// シフト0の値をx1、シフト1の値をx2、、、シフト(n-1)の値をxnに代入して、直後データyを計算する。
//
// 
// ※ 出力が、次の複数個の予測値を返すバージョン
bool calc_NextData_MRA(int    datatype,    // 直近データの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                       int    mTimeframe,  // 取得するデータの時間軸。
                       int    mDegree,
                       int    mDatanum,    // 予測に使用するデータ件数
                       double &calcData[]  // 出力：直後以降も含めた予測データ
                       ) {
   // 次数が1以下の時は計算しない。
   if(MAX_MRA_DEGREE <= 1) {
      printf("[%d]JIKKENエラー 重回帰分析用次数MRA_DEGREEE=%dが、1以下", __LINE__, MAX_MRA_DEGREE);   
      return false;
   }
   // データ数が次数＋１以下の時は、計算しない。
   if(MAX_MRA_EXP_DATA_NUM <= MAX_MRA_DEGREE + 1) {
      printf("[%d]JIKKENエラー 重回帰分析用データ数MRA_DATA_NUM=%d が、次数MRA_DEGREEE=%d+1以下", __LINE__, MAX_MRA_EXP_DATA_NUM, MAX_MRA_DEGREE);   
      return false;
   }

   double exp_matrix[MAX_MRA_EXP_DATA_NUM][MAX_MRA_DEGREE];
   double res_matrix[MAX_MRA_EXP_DATA_NUM];
   ArrayInitialize(exp_matrix, DOUBLE_VALUE_MIN);
   ArrayInitialize(res_matrix, DOUBLE_VALUE_MIN);

   create_ExpMatrix(datatype,  // 説明変数に入れるデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                    mTimeframe,
                    exp_matrix, // 出力:説明変数の入る配列四値やRSI、MAなど
                    mDegree,     // 出力:次数
                    mDatanum     // 出力:データ件数
                   );
                      
   // 目的変数（1列datanum行）のデータを引数res_matrixにセットする。
   create_ResMatrix(datatype,  // 目的変数に入れるデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                    mTimeframe,
                    res_matrix, // 出力:目的変数の入る配列四値やRSI、MAなど
                    mDatanum     // 出力:データ件数                   
                   );


   // 重回帰分析により、slope及びinterceptを計算する。
   double slope[MAX_MRA_EXP_DATA_NUM];
   double intercept;
   calc_Multiple_regression_analysis(exp_matrix, // 説明変数
                                     mDegree,     // 説明変数の次数。x1～x3であれば、3
                                     mDatanum,    // 説明変数の個数。100件のデータなど
                                     res_matrix, // 目的変数
                                     slope,      // 出力：係数=b1, b2, b3...
                                     intercept   // 出力：切片=b0
                                     );   
   int i;
   
   // slope[]に掛けるデータ。計算した将来値を先頭にコピーし、残りは、シフト0以降の値をコピーする。
   // 最初の将来値を計算するときは、param[0]=シフト０、[1]=シフト1、[2]=シフト２・・・
   // 2つ目の将来値を計算するときは、param[1]=1つ目の将来値、[1]=シフト0、[2]=シフト1・・・
   // 3つ目の将来値を計算するときは、param[2]=2つ目の将来値、[1]=1つ目の将来値、[2]=シフト0・・・
   double param[MAX_MRA_EXP_DATA_NUM];
   ArrayInitialize(param, DOUBLE_VALUE_MIN);
   int count1 = 0; // 計算済みの将来値の個数
   
   for(i = 0; i < mDegree; i++) {
      // param[]に計算済みの将来値を逆順でコピーする
      for(int m = 0; m < count1; m++) {
         param[m] = calcData[count1 - 1 - m];
      }
      // param[count - 1]以降は、シフト0以降の値をコピーする
      for(int p = count1; p < mDegree; p++) {
         param[p] = get_EachTypeValue(datatype, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                      mTimeframe,// 取得するデータの時間軸。
                                      p - count1         // 取得するデータのシフト。
                                      );
      }
//for(int ii = 0; ii < mDegree; ii++) {
//   printf("[%d]STA param[%d]=%s", __LINE__, ii, DoubleToString(param[ii], 8));   
//}      
      
      // count1番目の将来値を計算し、calcData[count1]に入れる
      calcData[i] = intercept;
      for(int j = 0; j < mDegree; j++) {
         calcData[i] = calcData[i] + slope[j] * param[j];
      }
//printf("[%d]STA i=%d >%d<番目の将来値=%s", __LINE__, i, count1, DoubleToString(calcData[i], 6));   

      // 計算した将来値の数をカウントアップ
      count1++;
      
   }

   return true;

}


// ※ 出力が、次の予測値1を返すバージョン
bool calc_NextData_MRA_VariousData
                      (int    datatype,  // 直近データの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                       int    mTimeframe,// 取得するデータの時間軸。原則として、0=PERIOD_CURRENT
//                       int    mDegree,     // 説明変数の次数。次数は、データパターンにより決まるため、廃止
                       int    mExp_Matrix_pattern, // 説明変数のデータパターン　1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, slopeH4
                       int    mDatanum,    // 予測に使用するデータ件数
                       double &calcData  // 出力：直後のデータ
                       ) {

   int i;
   // 次数が1以下の時は計算しない。
   if(MAX_MRA_DEGREE <= 1) {
      printf("[%d]JIKKENエラー 重回帰分析用次数MRA_DEGREEE=%dが、1以下", __LINE__, MAX_MRA_DEGREE);   
      return false;
   }
   // データ数が次数＋１以下の時は、計算しない。
   if(MAX_MRA_EXP_DATA_NUM <= MAX_MRA_DEGREE + 1) {
      printf("[%d]JIKKENエラー 重回帰分析用データ数MRA_DATA_NUM=%d が、次数MRA_DEGREEE=%d+1以下", __LINE__, MAX_MRA_EXP_DATA_NUM, MAX_MRA_DEGREE);   
      return false;
   }

   double exp_matrix[MAX_MRA_EXP_DATA_NUM][MAX_MRA_DEGREE];
   double res_matrix[MAX_MRA_EXP_DATA_NUM];
   ArrayInitialize(exp_matrix, DOUBLE_VALUE_MIN);
   ArrayInitialize(res_matrix, DOUBLE_VALUE_MIN);
   int degree = 0;
//printf("[%d]STA calc_NextData_MRA_VariousDataのmExp_Matrix_pattern=>%d<", __LINE__, mExp_Matrix_pattern);                      
   
   create_ExpMatrix_VariousData
                   (datatype,            // 説明変数に入れるデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                    mTimeframe,          // 取得するデータの時間軸。
                    mExp_Matrix_pattern, // 説明変数のデータパターン　1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, slopeH4
                    exp_matrix,          // 出力:説明変数の入る配列四値やRSI、MAなど
                    degree,             // 説明変数の次数。次数は、データパターンにより異なる。データパターン１の時は、4
                    mDatanum             // 出力:データ件数
                   );
//printf("[%d]STA create_ExpMatrix_VariousDataで計算したdegree=>%d<", __LINE__, degree);                      
/*
int i;
int j;
for(i = 0; i < 4; i++) {
   for(j = 0; j < mDatanum; j++) {
printf("[%d]STA exp_matrix[%d][%d]=%s", __LINE__, j, i, DoubleToStr(exp_matrix[j][i], 5));       
   }
   
}    
*/                  
   // 目的変数（1列datanum行）のデータを引数res_matrixにセットする。
   create_ResMatrix(datatype,  // 目的変数に入れるシフト0以降のデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                    mTimeframe,
                    res_matrix, // 出力:目的変数の入る配列四値やRSI、MAなど。res_matrix[0]は、シフト0のデータ　←　説明変数exp_matrix[0][]は、シフト１のデータ
                    mDatanum     // 出力:データ件数                   
                   );
/*
int i;
for(i = 0; i < mDatanum; i++) {
printf("[%d]STA res_matrix[%d]=%s", __LINE__, i, DoubleToStr(res_matrix[i], 5));       
}
*/
   // 重回帰分析により、slope及びinterceptを計算する。
   double slope[MAX_MRA_EXP_DATA_NUM];
   double intercept;
   calc_Multiple_regression_analysis(exp_matrix, // 説明変数
                                     degree,     // 説明変数の次数。x1～x3であれば、3
                                     mDatanum,    // 説明変数の個数。100件のデータなど
                                     res_matrix, // 目的変数
                                     slope,      // 出力：係数=b1, b2, b3...
                                     intercept   // 出力：切片=b0
                                     );   


   
/*      for(i = 0; i < degree; i++) {
      printf("[%d]STA 結果slope[%d]=%s", __LINE__, i, DoubleToString(slope[i], 8));   
   }
   printf("[%d]STA 結果intercept=%s", __LINE__, DoubleToString(intercept, 20));
*/
   // 予測データy = b0 + b1*x1 + b2*x2 + b3*x3 + ・・・　+ bn*xnを計算する
   calcData = intercept;
   double Xn[MAX_MRA_EXP_DATA_NUM]; // 予測データを計算する際のx1, x2, x3, ,,, xnを代入する。 
   ArrayInitialize(Xn, DOUBLE_VALUE_MIN);
   if(mExp_Matrix_pattern == 1) {
      // 1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, slopeH4
      Xn[0] = get_EachTypeValue(TYPE_MA5_MA25, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,    // 取得するデータの時間軸。
                                0              // 取得するデータのシフト。
                                );
      Xn[1] = get_EachTypeValue(TYPE_MACD_SIG, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,    // 取得するデータの時間軸。
                                0              // 取得するデータのシフト。
                                );
      Xn[2] = get_EachTypeValue(TYPE_BBUP_BBDOWN, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,       // 取得するデータの時間軸。
                                0                 // 取得するデータのシフト。
                                );
      Xn[3] = get_EachTypeValue(TYPE_SLOPEH4, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,    // 取得するデータの時間軸。
                                0              // 取得するデータのシフト。
                                );
   }
   else if(mExp_Matrix_pattern == 2) {
      // 1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, RSI
      Xn[0] = get_EachTypeValue(TYPE_MA5_MA25, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,    // 取得するデータの時間軸。
                                0              // 取得するデータのシフト。
                                );
      Xn[1] = get_EachTypeValue(TYPE_MACD_SIG, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,    // 取得するデータの時間軸。
                                0              // 取得するデータのシフト。
                                );
      Xn[2] = get_EachTypeValue(TYPE_BBUP_BBDOWN, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,       // 取得するデータの時間軸。
                                0                 // 取得するデータのシフト。
                                );
      Xn[3] = get_EachTypeValue(TYPE_RSI, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,    // 取得するデータの時間軸。
                                0              // 取得するデータのシフト。
                                );
   }   
   else if(mExp_Matrix_pattern == 3) {
      // 1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, RSI
      Xn[0] = get_EachTypeValue(TYPE_MA5_MA25, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,    // 取得するデータの時間軸。
                                0              // 取得するデータのシフト。
                                );
      Xn[1] = get_EachTypeValue(TYPE_MACD_SIG, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,    // 取得するデータの時間軸。
                                0              // 取得するデータのシフト。
                                );
      Xn[2] = get_EachTypeValue(TYPE_BBUP_BBDOWN, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,       // 取得するデータの時間軸。
                                0                 // 取得するデータのシフト。
                                );
      Xn[3] = get_EachTypeValue(TYPE_SLOPEH4, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,    // 取得するデータの時間軸。
                                0              // 取得するデータのシフト。
                                );
      Xn[4] = get_EachTypeValue(TYPE_RSI, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                mTimeframe,    // 取得するデータの時間軸。
                                0              // 取得するデータのシフト。
                                );
   }  /*   for(i = 0; i < degree; i++) {
      printf("[%d]STA Xn[%d]=%s", __LINE__, i, DoubleToString(Xn[i], global_Digits));
   }*/
   
   for(i = 0; i < degree; i++) {
      calcData = calcData + slope[i] * Xn[i];
   }
   
   return true;

}

// 重回帰分析を使った、直後データの予測
// MRAは、Multiple_regression_analysisの略。
// 重回帰分析により、重回帰式 y = b0 + b1*x1 + b2*x2 + b3*x3 + ・・・　+ bn*xn(ただし、nはMRA_DEGREE）を満たすb0, b1, b2, b3,,,bnを計算し、
// シフト0の値をx1、シフト1の値をx2、、、シフト(n-1)の値をxnに代入して、直後データyを計算する。
//
// 
// ※ 出力が、次の複数個の予測値を返すバージョン
bool calc_NextData_MRA_VariousData
                      (int    datatype,    // 予測するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                       int    mTimeframe,  // 取得するデータの時間軸。
//                       int    mDegree,     // 説明変数の次数。次数は、データパターンにより決まるため、廃止
                       int    mExp_Matrix_pattern, // 説明変数のデータパターン　1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, slopeH4
                       int    mDatanum,    // 予測に使用するデータ件数
                       double &calcData[]  // 出力：直後以降も含めた予測データ
                       ) {
   // 次数が1以下の時は計算しない。
   if(MAX_MRA_DEGREE <= 1) {
      printf("[%d]JIKKENエラー 重回帰分析用次数MRA_DEGREEE=%dが、1以下", __LINE__, MAX_MRA_DEGREE);   
      return false;
   }
   // データ数が次数＋１以下の時は、計算しない。
   if(MAX_MRA_EXP_DATA_NUM <= MAX_MRA_DEGREE + 1) {
      printf("[%d]JIKKENエラー 重回帰分析用データ数MRA_DATA_NUM=%d が、次数MRA_DEGREEE=%d+1以下", __LINE__, MAX_MRA_EXP_DATA_NUM, MAX_MRA_DEGREE);   
      return false;
   }

   double exp_matrix[MAX_MRA_EXP_DATA_NUM][MAX_MRA_DEGREE];
   double res_matrix[MAX_MRA_EXP_DATA_NUM];
   ArrayInitialize(exp_matrix, DOUBLE_VALUE_MIN);
   ArrayInitialize(res_matrix, DOUBLE_VALUE_MIN);

   // 目的変数（1列datanum行）のデータを引数create_ExpMatrixにセットする。
   int degree = 0;
   create_ExpMatrix_VariousData
                   (datatype,            // 説明変数に入れるデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                    mTimeframe,          // 取得するデータの時間軸。
                    mExp_Matrix_pattern, // 説明変数のデータパターン　1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, slopeH4
                    exp_matrix,          // 出力:説明変数の入る配列四値やRSI、MAなど
                    degree,             //  出力：説明変数の次数。次数は、データパターンにより異なる。データパターン１の時は、4
                    mDatanum             // 出力:データ件数
                   );
//printf("[%d]STA degree=%d", __LINE__, degree);                   
   // 目的変数（1列datanum行）のデータを引数res_matrixにセットする。
   create_ResMatrix(datatype,  // 目的変数に入れるデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                    mTimeframe,
                    res_matrix, // 出力:目的変数の入る配列四値やRSI、MAなど
                    mDatanum     // 出力:データ件数                   
                   );


   // 重回帰分析により、slope及びinterceptを計算する。
   double slope[MAX_MRA_EXP_DATA_NUM];
   double intercept;
   calc_Multiple_regression_analysis(exp_matrix, // 説明変数
                                     degree,     // 説明変数の次数。x1～x3であれば、3
                                     mDatanum,    // 説明変数の個数。100件のデータなど
                                     res_matrix, // 目的変数
                                     slope,      // 出力：係数=b1, b2, b3...
                                     intercept   // 出力：切片=b0
                                     );   
   int i;
   
   // slope[]に掛けるデータ。計算した将来値を先頭にコピーし、残りは、シフト0以降の値をコピーする。
   // 最初の将来値を計算するときは、param[0]=シフト０、[1]=シフト1、[2]=シフト２・・・
   // 2つ目の将来値を計算するときは、param[1]=1つ目の将来値、[1]=シフト0、[2]=シフト1・・・
   // 3つ目の将来値を計算するときは、param[2]=2つ目の将来値、[1]=1つ目の将来値、[2]=シフト0・・・
   double param[MAX_MRA_EXP_DATA_NUM];
   ArrayInitialize(param, DOUBLE_VALUE_MIN);
   int count1 = 0; // 計算済みの将来値の個数
   
   for(i = 0; i < degree; i++) {
      // param[]に計算済みの将来値を逆順でコピーする
      for(int m = 0; m < count1; m++) {
         param[m] = calcData[count1 - 1 - m];
      }
      // param[count - 1]以降は、シフト0以降の値をコピーする
      for(int p = count1; p < degree; p++) {
         param[p] = get_EachTypeValue(datatype, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                                      mTimeframe,// 取得するデータの時間軸。
                                      p - count1         // 取得するデータのシフト。
                                      );
      }
    
      
      // count1番目の将来値を計算し、calcData[count1]に入れる
      calcData[i] = intercept;
      for(int j = 0; j < degree; j++) {
         calcData[i] = calcData[i] + slope[j] * param[j];
      }

      // 計算した将来値の数をカウントアップ
      count1++;
      
   }

   return true;

}



double get_EachTypeValue(int mDatatype, // 取得するデータの種類。TYPE_OPEN、TYPE_HIGH、TYPE_LOW、TYPE_CLOSEなど
                         int mTimeframe,// 取得するデータの時間軸。
                         int mShift     // 取得するデータのシフト。
                      ) {
   double ret = DOUBLE_VALUE_MIN;
   string symbol = Symbol();

   if(mDatatype == TYPE_OPEN) {
      ret = iOpen(symbol, mTimeframe, mShift);
   }
   else if(mDatatype == TYPE_HIGH) {
      ret = iHigh(symbol, mTimeframe, mShift);
   }
   else if(mDatatype == TYPE_LOW) {
      ret = iLow(symbol, mTimeframe, mShift);
   }
   else if(mDatatype == TYPE_CLOSE) {
      ret = iClose(symbol, mTimeframe, mShift);
   }
   else if(mDatatype == TYPE_MA5_MA25) {
       double ma5 = iMA(
                         NULL,        // 通貨ペア
                         mTimeframe,  // 時間軸
                         5,           // MAの平均期間
                         0,           // MAシフト
                         MODE_SMMA,   // MAの平均化メソッド
                         PRICE_CLOSE, // 適用価格
                         mShift       // シフト
                        );
       double ma25 = iMA(
                         NULL,        // 通貨ペア
                         mTimeframe,  // 時間軸
                         25,          // MAの平均期間
                         0,           // MAシフト
                         MODE_SMMA,   // MAの平均化メソッド
                         PRICE_CLOSE, // 適用価格
                         mShift       // シフト
                        );  
      ret = ma5 - ma25;                                              
   }
   else if(mDatatype == TYPE_MACD_SIG) {
      double MACD_1   = iMACD(NULL,0,12,26,9,0,0,mShift);
      // double MACD_2   = iMACD(NULL,0,12,26,9,0,0,mShift+1);
      double Signal_1 = iMACD(NULL,0,12,26,9,0,1,mShift);
      // double Signal_2 = iMACD(NULL,0,12,26,9,0,1,mShift+1);
      ret = MACD_1 - Signal_1;
   }
   else if(mDatatype == TYPE_BBUP_BBDOWN) {
      double upper = iBands(
                              NULL,         // 通貨ペア
                              mTimeframe,   // 時間軸
                              20,           // 平均期間
                              2,            // 標準偏差
                              0,            // バンドシフト
                              PRICE_CLOSE,  // 適用価格
                              MODE_UPPER,   // ラインインデックス
                              mShift        // シフト
                             );
      double lower = iBands(
                              NULL,         // 通貨ペア
                              mTimeframe,   // 時間軸
                              20,           // 平均期間
                              2,            // 標準偏差
                              0,            // バンドシフト
                              PRICE_CLOSE,  // 適用価格
                              MODE_LOWER,   // ラインインデックス
                              mShift        // シフト
                             );
      ret = upper - lower;
   }   
   else if(mDatatype == TYPE_SLOPEH4) {
      double EMA_1 = NormalizeDouble(iMA(global_Symbol,mTimeframe,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 0), global_Digits);
      double EMA_2 = NormalizeDouble(iMA(global_Symbol,mTimeframe,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 1), global_Digits);	
      double EMA_3 = NormalizeDouble(iMA(global_Symbol,mTimeframe,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 2), global_Digits);	
      double EMA_4 = NormalizeDouble(iMA(global_Symbol,mTimeframe,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 3), global_Digits);	
      double EMA_5 = NormalizeDouble(iMA(global_Symbol,mTimeframe,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 4), global_Digits);	
   	
      double data[5];
      ArrayInitialize(data, 0.0);
      data[0] = EMA_5;  // 配列に古い順に代入
      data[1] = EMA_4;
      data[2] = EMA_3;
      data[3] = EMA_2;
      data[4] = EMA_1;
   
      double slope     = DOUBLE_VALUE_MIN;
      double intercept = DOUBLE_VALUE_MIN; 
      // 候補が、配列に古い順に入っているので、傾きslopeをそのまま使うことができる。
   
      bool flag =  calcRegressionLine(data, 5, slope, intercept);
      
      ret = slope;
   }   
   else if(mDatatype == TYPE_RSI) {
      ret = iRSI(global_Symbol, // 通貨ペア
                 mTimeframe,    // 時間軸
                 14,            // 平均期間
                 PRICE_CLOSE,   // 適用価格
                 mShift         // シフト
                );
   }
   else if(mDatatype == TYPE_DMI) {
   // ＋DI 上昇トレンドである可能性を判断します
   // －DI 下降トレンドである可能性を判断します
   // ＋DIが－DIを下から上に上抜いたら買いシグナル
   // ＋DIが－DIを上から下に下抜いたら売りシグナル
   // ※＋DIと－DIの幅が大きいほどトレンドが強いことを示しています。
   // つまり、＋DIが最高値にあり－DIが最低値にある時は、非常に強い上昇トレンドであると判断できます。
   double plusDI = iADX(global_Symbol,// 通貨ペア 
                        mTimeframe,   // 時間軸
                        14,           // 計算期間
                        PRICE_CLOSE,  //　適用価格
                        MODE_PLUSDI,  // ライン種類
                        mShift        // シフト
                        );
   double minusDI = iADX(global_Symbol,// 通貨ペア 
                         mTimeframe,   // 時間軸
                         14,           // 計算期間
                         PRICE_CLOSE,  //　適用価格
                         MODE_MINUSDI,  // ライン種類
                         mShift        // シフト
                        ); 
   ret = plusDI - minusDI;
printf("[%d]STA plusDI=%s  minusDI=%s --> %s", __LINE__, 
      DoubleToStr(plusDI, 5),
      DoubleToStr(minusDI, 5),
      DoubleToStr(ret, 5)
      );    
   }      
   return ret;
}




