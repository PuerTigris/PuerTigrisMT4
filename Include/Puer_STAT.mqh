//
// 20211213 DBアクセス部分を削除。過去1000件以上のデータを使ったテストは、PuellaTigrisST_004で行う。
//

//+------------------------------------------------------------------+	
//|  　　　　　　　　　　　　　　　　　　　　　　　　　　　                              |
//|  Copyright (c) 2016 トラの親 All rights reserved.                |	
//|                                                                  |
//+------------------------------------------------------------------+	
//+------------------------------------------------------------------+	
//| ヘッダーファイル読込                                             |	
//+------------------------------------------------------------------+	
#include <Tigris_COMMON.mqh>
#include <Tigris_Statistics.mqh>

//#include <MQLMySQL.mqh>

//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	
#define MAX_POP_NUM    90000
#define MINIMAL_POP_NUM 3

//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
//
// 外部パラメタからの引継ぎ。
// ＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊
// ＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊最適化は、PuerTigrisは使わず、PuellaTigrisSTを使うこと。＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊
//　＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊＊
int POP_NUM   = 1000; //母集団の数。実行時点から何本前の足までを統計分析の対象とするか。
                      // 2015年10月27日火曜日[MT4プログラミング]小ネタ バックテスト時のiCloseは1000本前までに限定される。
                      // http://mt4program.blogspot.com/2015/10/mt4-iclose1000.html
int RANGE_NUM = 20;   //発生した価格帯をいくつのレンジに分割するか。
double SIGMA  = 3;    // SellLine, BuyLine計算時に使用する。


//
// 外部パラメータ以外
//
bool global_MailFlag        = true;           //確定損益メールの送信フラグ。trueで送信する。						

// DB接続用変数
/*
int Port;
int ClientFlag;
string Host;
string User;
string Password;
string Database;
string Socket; 
int DB; // database identifier
string INI;
*/

struct st_OccuredNoTable{  //各価格帯の発生件数を保持するための構造体。
   double occurNO; //iClose(Symbol(),PERIOD_M1,shiftNo) - iClose(Symbol(),PERIOD_M1,shiftNo+1)
   double priceFrom;  //いくら以上を発生件数にカウントしたか。
   double priceTo;    //いくら"未満"（←以下ではないので注意）を発生件数にカウントしたか。
   double priceRepresentative; //カウントした範囲の代表値＝(priceFrom+priceTo)/2
};

string STMainBuf = "";

struct st_PoplationTable2{  // 母集団データを保持するための構造体。
   double divValue;        // iClose(Symbol(),タイムフレーム, シフトNo+1) - iClose(Symbol(),タイムフレーム, シフトNo)の値。
   datetime dateTime;       // shiftの時間。iTime(Symbol(),タイムフレーム, シフトNo)
};
st_PoplationTable2 PoplationTable_rows2[MAX_POP_NUM];   //DB登録済みレートデータ。




//+------------------------------------------------------------------+
//|   No.22 tradeStatistics2()                                               |
//+------------------------------------------------------------------+  
// 引数pastSpanは、時間軸。
int tradeStatistics2(int pastSpan) {
   int pop_num = POP_NUM;
   int rangeNum = RANGE_NUM;

   bool flag = false;
   int BuySell = NO_SIGNAL;
   double SellLine = 0.0;
   double BuyLine  = 0.0;
   
   flag = getTradeLine(pop_num, rangeNum, pastSpan, SellLine, BuyLine);
   if(flag == false) {
      return NO_SIGNAL;
   }
   double div = NormalizeDouble(iClose(global_Symbol, 0, 0), global_Digits)  - NormalizeDouble(iClose(global_Symbol, 0, 1), global_Digits) ;
   // mail送信用
   STMainBuf = "直前の取引判定基準" + "\n";

   STMainBuf = "差分(シフト1 - シフト2)=" + DoubleToStr(NormalizeDouble(div, global_Digits)) + "\n";

   STMainBuf =  STMainBuf + "差分が、平均 ＋ 標準偏差（σ）× " + DoubleToStr(SIGMA) + "＝" + DoubleToStr(NormalizeDouble(SellLine, global_Digits)) + "以上でショート\n";
   STMainBuf =  STMainBuf + "差分が、平均 ー 標準偏差（σ）× " + DoubleToStr(SIGMA) + "＝" + DoubleToStr(NormalizeDouble(BuyLine, global_Digits)) + "以下でロング\n"; 

   if(NormalizeDouble(div, global_Digits) >= NormalizeDouble(SellLine, global_Digits) && NormalizeDouble(SellLine, global_Digits) > 0.0) {
      BuySell = SELL_SIGNAL;
   }
   else if(NormalizeDouble(div, global_Digits) <= NormalizeDouble(BuyLine, global_Digits) && NormalizeDouble(div, global_Digits) > 0.0) {
      BuySell = BUY_SIGNAL;
   }

   return BuySell;
   
}
//-------------------------------------------------

// 
// 引数：pop_num＝母数の個数。rangeNum＝母数をいくつに分割したか。pastSpan＝時間軸。
//     メモ：pop_numは、データPoplationTable_rowsの件数と同じ。rangeNumは、発生した差額occurの件数と同じ。
//     SellLine=差額がこの値以上の時、統計的に発生しづらい大幅上昇中。下落が見込まれるため、売り。
//     SellLine=差額がこの値以下の時、統計的に発生しづらい下落上昇中。上昇が見込まれるため、買い。
// 返り値：失敗したらfalse。それ以外はtrue。
bool getTradeLine(int pop_num, int rangeNum,int pastSpan, double &SellLine, double &BuyLine){
   SellLine = 0.0;
   BuyLine  = 0.0;
   if(pop_num < MINIMAL_POP_NUM) {
      printf( "[%d]エラー　母集団が十分な個数無い。:母集団=%s件" , __LINE__ , IntegerToString(pop_num));
      return false;
   }  


   int i;
   int j;
   double digits = global_Digits;
   int initial_rangeNum = rangeNum;

   //過去POP_NUM(population＝母集団）件数前のClose値が0より大きければ、以下を実行する。
   if(IsTesting() == true) {
   }
   else {
      double firstClose = iClose( global_Symbol, pastSpan , pop_num);
      if(firstClose <= 0) {
         printf( "[%d]エラー　%s時点のデータ取得失敗" , __LINE__ , TimeToString(iTime(global_Symbol, pastSpan, pop_num)));
         return false;
      }
   }

   //
   // PoplationTable_rowsを作成する。
   // 
   // 初期化（-1を代入）する。
   for(i = 0; i < pop_num+1; i++) {
      // PoplationTable_rows[0]=初回更新時点。
      // PoplationTable_rows[1]=初回更新時の1つ前。
      // PoplationTable_rows[2]=初回更新時の2つ前。
//      PoplationTable_rows2[i].shiftNo   = -1;  // shiftNoは、必要ないのでは？
      PoplationTable_rows2[i].divValue  = -1;
      PoplationTable_rows2[i].dateTime  = -1;
   }


   // 当初、for(i = 0; i < pop_num; i++) で全てのPoplationTable_rows[i]を全件取得しなおしていたが、
   // 全件取得は初回のみとした。
   // 初回以外（PoplationTable_rows[0]が0より大きい場合）は、
   // PoplationTable_rows[1]は、前回更新時のPoplationTable_rows[0]
   // PoplationTable_rows[2]は、前回更新時のPoplationTable_rows[1]
   // PoplationTable_rows[0]に更新時点の値を取得、
   // とする。

   updatePoptable(global_Symbol, Period(), pastSpan, pop_num);

//   
//    
// ファイル出力   
//   
//    
/*
 int fileHandle1 = FileOpen("PoplationTable_rows.csv", FILE_WRITE | FILE_CSV ,",");
 double bufData[];
 ArrayResize(bufData, pop_num);
 if(fileHandle1 != INVALID_HANDLE){
   //省略
   for(i = 0; i < pop_num; i++) {      
      FileWrite(fileHandle1 , 
         i,
         PoplationTable_rows2[i].divValue);
      bufData[i] = PoplationTable_rows2[i].divValue;
   }
   double fileMean = 0.0;
   double fileSigma = 0.0;
   
   calcMeanAndSigma(bufData, pop_num, fileMean, fileSigma);
   printf( "[%d]平均=%s 分散=%s" , __LINE__, DoubleToStr(fileMean), DoubleToStr(fileSigma));
   
   FileWrite(fileHandle1 , 
   "平均", fileMean,
   "σ", fileSigma);
 }
 else {
   printf( "[%d]ファイルオープンエラー：PoplationTable_rows" , __LINE__);
   Print(GetLastError());
 }    
 FileClose(fileHandle1);   
      
*/
    
   //
   // 母集団から異常値を削除する。→　そのあとで、度数分布表を作成する
   //
   //
   //差分PoplationTable_rows[i].divValueの最小値を外し、残りの部分で計算した（平均-3σ）が外した最小値以上であれば、
   //外した値が異例な値と判断し、その値を除外する。
   //   除外候補removeCandをmin(PoplationTable_rows[i].divValue)とする。
   //   removeCand > 0の間、以下を繰り返す。
   //      除外候補removeCandを除いたデータ群から求める（差額の平均 - 3σ）と除外候補removeCandを比較して、
   //      ①（差額の平均 - 3σ） > removeCandならば、差分PoplationTable_rows[i]からremoveCandを除外する。
   //   　    除外時は、差分PoplationTable_rows[i]←[i+1] (iは、1～rangeNum-1。）と上書きし、rangeNum = rangeNum - 1とする。
   //         新しい除外候補removeCandをmin(PoplationTable_rows[i].divValue)とする。
   //      ② 除外候補removeCand = 0.0;とし、whileのループから脱出する。
   // 
   // 異常に小さい値を削除する。　　  
   //   除外候補removeCandをmin(PoplationTable_rows[i].divValue)とする。
   double removeCand = getMinDivValue(PoplationTable_rows2, pop_num);
   double sigma = 0.0;
   double mean  = 0.0;
   double mean3sigma = 0.0;
   double calcBuf[];

   while(NormalizeDouble(removeCand, global_Digits) < NormalizeDouble(DOUBLE_VALUE_MAX, global_Digits)) {
      //      除外候補removeCandを除いたデータ群から求める（差額の平均 - 3σ）と除外候補removeCandを比較して、
      ArrayResize(calcBuf, pop_num);
      int count = 0;
      for(i = 0; i < pop_num; i++) {
         if(NormalizeDouble(removeCand, global_Digits) < NormalizeDouble(PoplationTable_rows2[i].divValue, global_Digits) ){
            calcBuf[count] = PoplationTable_rows2[i].divValue;
            count++;
         }
      }
      bool flag = false;
      flag = calcMeanAndSigma(calcBuf, count - 1, mean, sigma); 
      if(flag == false) {
         return false;
      }
      mean3sigma = mean - 3 * sigma;

      if(NormalizeDouble(removeCand, global_Digits) < NormalizeDouble(mean3sigma, global_Digits)) {
         for(i = 0; i < pop_num; i++) {
            double bufDivValue = PoplationTable_rows2[i].divValue;
            if(NormalizeDouble(bufDivValue, global_Digits) == NormalizeDouble(removeCand, global_Digits)) {
               for(j = i; j < pop_num - 1; j++) {
                  PoplationTable_rows2[j] = PoplationTable_rows2[j+1];
               }
               pop_num = pop_num - 1;
            }
         }
         // 削除したので次の除外候補を探す
         removeCand = getMinDivValue(PoplationTable_rows2, pop_num);
      }
      // 削除しなかったので、ループを抜けるため、最大値を設定する。
      else {
         removeCand = DOUBLE_VALUE_MAX;
      }
   }


   // 異常に大きい値を削除する。　　  
   //   除外候補removeCandをman(PoplationTable_rows[i].divValue)とする。
   double removeCand_Max = getMaxDivValue(PoplationTable_rows2, pop_num);
   double sigma_Max = 0.0;
   double mean_Max  = 0.0;
   double mean3sigma_Max = 0.0;
   double calcBuf_Max[];
//printf( "[%d]テスト 大きな削除候補=%s  " , __LINE__ , DoubleToStr(removeCand_Max));

   while(NormalizeDouble(removeCand_Max, global_Digits) > NormalizeDouble(DOUBLE_VALUE_MIN, global_Digits)) {
      //      除外候補removeCandを除いたデータ群から求める（差額の平均 - 3σ）と除外候補removeCandを比較して、
      ArrayResize(calcBuf_Max, pop_num);
      int count_Max = 0;
      for(i = 0; i < pop_num; i++) {
         if(NormalizeDouble(removeCand_Max, global_Digits) > NormalizeDouble(PoplationTable_rows2[i].divValue, global_Digits) ){
            calcBuf_Max[count_Max] = PoplationTable_rows2[i].divValue;
//printf( "[%d]テスト 大きな削除候補用=calcBuf_Max[%d]=%s" , __LINE__ , count_Max, DoubleToStr(calcBuf_Max[count_Max]));
            
            count_Max++;
         }
      }
      bool flag2 = false;
      flag2 = calcMeanAndSigma(calcBuf_Max, count_Max - 1, mean_Max, sigma_Max); 
      if(flag2 == false) {
         return false;
      }

      mean3sigma_Max = mean_Max + 3 * sigma_Max;
//printf( "[%d]テスト 大きな削除候補=%s　mean_Max=%s　sigma_Max=%s mean3sigma_Max=%s" , __LINE__ , DoubleToStr(removeCand_Max), DoubleToStr(mean_Max), DoubleToStr(sigma_Max),DoubleToStr(mean3sigma_Max));
      if(NormalizeDouble(removeCand_Max, global_Digits) > NormalizeDouble(mean3sigma_Max, global_Digits)) {
         for(i = 0; i < pop_num; i++) {
            double bufDivValue_MAX = PoplationTable_rows2[i].divValue;
            if(NormalizeDouble(bufDivValue_MAX, global_Digits) == NormalizeDouble(removeCand_Max, global_Digits)) {
               for(int j2 = i; j2 < pop_num - 1; j2++) {
                  PoplationTable_rows2[j2] = PoplationTable_rows2[j2+1];
               }
               pop_num = pop_num - 1;
            }
         }
         // 削除したので次の除外候補を探す
         removeCand_Max = getMaxDivValue(PoplationTable_rows2, pop_num);
      }
      // 削除しなかったので、ループを抜けるため、最大値を設定する。
      else {
         removeCand_Max = DOUBLE_VALUE_MIN;
      }
   }


   //
   // occurを使って、分散を計算する。
   //
   st_OccuredNoTable occur[];
   ArrayResize(occur, pop_num);
   // 初期化
   for(i = 0; i < rangeNum+1; i++) {
      occur[i].priceFrom = -1;  //いくら以上カウントしたか
      occur[i].priceTo   = -1;  //いくら未満をカウントしたか。
      occur[i].priceRepresentative  = 0.0;  //代表値。
      occur[i].occurNO   = 0;               //発生件数
   }   
   // 差額の最大値、差額の最小値を計算する。
   double rangeMax = ERROR_VALUE_DOUBLE * (-1);
   double rangeMin = ERROR_VALUE_DOUBLE;
   double diffCurr_Before_i = 0.0;
   for(i = 0; i < pop_num; i++) {
      if(rangeMax < PoplationTable_rows2[i].divValue) {
         rangeMax = PoplationTable_rows2[i].divValue;
      }
      else if(rangeMin > PoplationTable_rows2[i].divValue) {
         rangeMin = PoplationTable_rows2[i].divValue;
      }
   }
   // rangeMax＝差額の最大値 =    // rangeMin + rangeValue * rangeNum
   //    occur[rangeNum]
   // rangeMin + rangeValue * (rangeNum - 1)
   //    occur[rangeNum - 1]
   // ・・・・
   // rangeMin + rangeValue * 2
   //    occur[2]
   // rangeMin + rangeValue * 1
   //    occur[1]
   // rangeMin＝差額の最小値
   double rangeValue = MathAbs((rangeMax - rangeMin) / rangeNum);  //1区間の幅   

   for(i = 0; i < rangeNum; i++) {  
      occur[i].priceFrom = NormalizeDouble(rangeMin, global_Digits)  + rangeValue * i;
      occur[i].priceTo   = NormalizeDouble(rangeMin, global_Digits)  + rangeValue * (i+1);
      occur[i].priceRepresentative   =  (NormalizeDouble(occur[i].priceFrom, global_Digits)  + NormalizeDouble(occur[i].priceTo, global_Digits) ) / 2.0;
   }
   //各範囲（From,To）に該当する件数を数える。
   double targetValue = ERROR_VALUE_DOUBLE * (-1);
   for(i = 0; i < pop_num; i++) {
      double bufPop = PoplationTable_rows2[i].divValue;

      for(j = 0; j < rangeNum; j++) {
         if(NormalizeDouble(occur[j].priceFrom, global_Digits) <= NormalizeDouble(bufPop, global_Digits)
            && NormalizeDouble(bufPop, global_Digits) < NormalizeDouble(occur[j].priceTo, global_Digits)) {
            occur[j].occurNO = occur[j].occurNO + 1;
         }
      }
   } 
      
/*      
 int fileHandle1 = FileOpen("PoplationTable_rows.csv", FILE_WRITE | FILE_CSV ,",");
 if(fileHandle1 != INVALID_HANDLE){
   //省略
   for(i = 0; i < pop_num; i++) {      
      FileWrite(fileHandle1 , 
         i,
         PoplationTable_rows2[i].divValue);
   }
 }
 else {
   printf( "[%d]ファイルオープンエラー：PoplationTable_rows" , __LINE__);
   Print(GetLastError());
 }    
 FileClose(fileHandle1);   

 int fileHandle2 = FileOpen("occur.csv", FILE_WRITE | FILE_CSV ,",");
  if(fileHandle1 != INVALID_HANDLE){
   //省略
   for(i = 0; i < rangeNum; i++) {      
      FileWrite(fileHandle1 , 
         i,
         occur[i].indexNo, occur[i].priceFrom, occur[i].priceTo, occur[i].priceRepresentative, occur[i].occurNO);
   }
 }
 else {
   printf( "[%d]ファイルオープンエラー：PoplationTable_rows" , __LINE__);
   Print(GetLastError());
 }    
 FileClose(fileHandle2);   
*/
   double bufDivValue2[][2];
   ArrayResize(bufDivValue2, rangeNum);
   for(i = 0; i < rangeNum; i++) {
      bufDivValue2[i][0] = occur[i].priceRepresentative;
      bufDivValue2[i][1] = occur[i].occurNO;
   }
   double sigma2 = 0.0;
   double mean2  = 0.0;   
   bool flagcalcMeanAndSigma = false;
   flagcalcMeanAndSigma = calcMeanAndSigma(bufDivValue2,rangeNum, mean2, sigma2);
   if(flagcalcMeanAndSigma == false) {
      return false;
   }
   
   SellLine = NormalizeDouble(mean2, global_Digits)  + SIGMA * sigma2;
   BuyLine  = NormalizeDouble(mean2, global_Digits)  - SIGMA * sigma2;         
   
   return true;
}



// 母集団が入った配列PoplationTable_rows2を更新する。
// テスト中は、iCloseが過去1000本目までのデータしか取得できないことから、母集団のデータ数pop_numが、
// 1000を超えている場合にデータベースから必要な値を取得する。
// 注）テスト中であってもpop_numが1000以下の場合はデータベースを使わない。
bool updatePoptable(string mSymbol, int timeframe, int pastSpan, int pop_num) {
   // timeframeが0の時は、Period()を使ってENUM_TIMEFRAMESに変換する。
   if(timeframe == 0) {
      timeframe = Period();
   }
   int i;

   // DBを使ってPoplationTable_rows2を更新する場合。
   if(IsTesting() == true && pop_num > 1000) {   
printf( "[%d]テスト DBを使ったテストをサポートしていません", __LINE__);
      //
      // 過去1000件以上のデータを使ったテストは、PuellaTigrisST_004で行う。
      //
   }
   // DBを使わないでPoplationTable_rows2を更新する場合。
   else {
      if(PoplationTable_rows2[0].divValue <= 0.0) {
         for(i = 0; i < pop_num; i++) {
            // 差分は、現在shift=0が100円、1つ過去shift=1が99円の時、+1円としたい。
            PoplationTable_rows2[i].divValue = NormalizeDouble(iClose(global_Symbol,pastSpan,i), global_Digits)  - NormalizeDouble(iClose(global_Symbol,pastSpan,i + 1), global_Digits) ;
            PoplationTable_rows2[i].dateTime = iTime(global_Symbol,pastSpan,i);
         }
      }
      else {
         // 配列の値を１つずつ後ろにずらす。
         for(i = pop_num - 1; i >= 1; i-- ) {
            PoplationTable_rows2[i].divValue = PoplationTable_rows2[i - 1].divValue;
            PoplationTable_rows2[i].dateTime = PoplationTable_rows2[i - 1].dateTime;       
         }
         // 配列の先頭（０番目）のみを更新する。
         i = 0;
         PoplationTable_rows2[i].divValue = NormalizeDouble(iClose(global_Symbol,pastSpan,i), global_Digits)  - NormalizeDouble(iClose(global_Symbol,pastSpan,i + 1), global_Digits) ;
         PoplationTable_rows2[i].dateTime = iTime(global_Symbol,pastSpan,i);         
      }
   }
   return true;
}




// PoplationTable_rows[].DivValueの最大値を求める。
double getMaxDivValue(st_PoplationTable2 &mPoplationTable_rows2[], int pop_num) {
   double maxDouble = DOUBLE_VALUE_MIN;
   
   for(int i = 0; i < pop_num; i++) {
      if(NormalizeDouble(maxDouble, global_Digits) < NormalizeDouble(mPoplationTable_rows2[i].divValue, global_Digits) ) {
         maxDouble = mPoplationTable_rows2[i].divValue;
      }
   }
   
   if(maxDouble > DOUBLE_VALUE_MIN) {
      return maxDouble;
   }
   else {
      return DOUBLE_VALUE_MIN;
   }
}


// PoplationTable_rows[].DivValueの最小値を求める。
double getMinDivValue(st_PoplationTable2 &mPoplationTable_rows2[], int pop_num) {
   double minDouble = DOUBLE_VALUE_MAX;
   
   for(int i = 0; i < pop_num; i++) {
      if(NormalizeDouble(minDouble, global_Digits) > NormalizeDouble(mPoplationTable_rows2[i].divValue, global_Digits) ) {
      
         minDouble = mPoplationTable_rows2[i].divValue;
      }
   }
   
   if(minDouble < DOUBLE_VALUE_MAX) {
      return minDouble;
   }
   else {
      return DOUBLE_VALUE_MAX;
   }
}

