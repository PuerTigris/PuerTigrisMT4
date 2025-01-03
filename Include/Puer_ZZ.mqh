//#property strict	

// 20220328 PuellaTigrisZZ_002.mq4から抜粋
// インジケータのZigzagを使った取引手法
// ※Zigzag計算関数UpdateZigZag()は、自作のため、値がおかしい場合は、インジケータを利用する。。
// 【戦略】
// ロングエントリー
// ・直前の山/谷が、谷
// ・2つ前の谷より直前の谷が、高い。＝安値が切り上がり中
// ・現在値が、直前の山よりも高い（＝ネックライン（高値）を超えた）ところでロングを実施。
// ・エントリー直後に、直前の谷をストップとする。
// ロング手じまい
// ・Zigzagの値を計算するたびに、直前の谷が、2つ前の谷より高ければ（安値切り上がり）、直前の谷をストップに更新する。
//   ＝エントリー時を合わせて、現時点のZigzag値を取得するたびに、
//      2つ前の谷より直前の谷が高ければ、ロングのストップを直前の谷に更新する。
// ・ロングの利益確定値(tp)は、設定しない。
//
// 
// ショートエントリー
// ・直前の山/谷が、山
// ・2つ前の山より直前の山が低い。＝高値切り下がり中。
// ・現在値が、直前の谷よりも低い（＝ネックライン（安値）を超えた）ところでショートを実施。
// ・エントリー直後に、直前の山をストップとする。
// ショート手じまい
// ・Zigzagの値を計算するたびに、直前の山が、2つ前の山より低ければ（高値切り下がり）、直前の谷をストップに更新する。
//   ＝エントリー時を合わせて、現時点のZigzag値を取得するたびに、
//      2つ前の山より直前の山が低ければ、ショートのストップを直前の山に更新する。
// ・ショートの利益確定値(tp)は、設定しない。


//+------------------------------------------------------------------+	
//|  Copyright (c) 2016 トラの親 All rights reserved.                |	
//|                                                                  |
//+------------------------------------------------------------------+	
//+------------------------------------------------------------------+	
//| ヘッダーファイル読込                                             |	
//+------------------------------------------------------------------+	
#include <Tigris_COMMON.mqh>
//#include <Tigris_VirtualTrade.mqh>
#include <Tigris_GLOBALS.mqh>

//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
/*
int ZigzagDepth = 12;
int ZigzagDeviation = 15;
int ZigzagBackstep = 9;
*/
//int AllowableErrorPoint =  30;   // Maximum distance between the twin tops/bottoms
double   ZigTop[5];     //ジグザグの山保存用。ZigTop[0]は最新の高値、ZigTop[1]は1つ前の高値。
datetime ZigTopTime[5]; //ジグザグの山の時間。
double   ZigBottom[5];  //ジグザグの谷保存用
datetime ZigBottomTime[5];  //ジグザグの谷保存用
int global_LastMountORBottom = ZIGZAG_NONE;  // 直近のZIGZAG計算結果で直近が山か谷か。

//EAを足の更新ごとに実行するための変数。
datetime execZZtime = 0;

//string PGName = "ZigzagTest";     //プログラム名				
//bool mMailFlag        = true;           //確定損益メールの送信フラグ。trueで送信する。						

   

// Zigzagの値を再計算するための変数
int global_rates_total_Bar = iBars(global_Symbol,0);
int global_prev_calculated_Bar = 0;

/*
double   ZigTop[5];     //ジグザグの山保存用。ZigTop[0]は最新の高値、ZigTop[1]は1つ前の高値。
datetime ZigTopTime[5]; //ジグザグの山の時間。
double   ZigBottom[5];  //ジグザグの谷保存用
datetime ZigBottomTime[5];  //ジグザグの谷保存用
int global_LastMountORBottom = ZIGZAG_NONE;  // 直近のZIGZAG計算結果で直近が山か谷か。
*/
int MountORBottom_MAIL; // 直前が山か谷か。メール出力用。
int TopPoint;
int BottomPoint;



//+------------------------------------------------------------------+
//|24.ZZ                                                 　　　   |
//+------------------------------------------------------------------+
int entryZZ() {
   if(ZigzagBackstep >= ZigzagDepth) {
      printf( "[%d]ZZ ZigZag.mq4のOnInit（）で、ZigzagBackstep=%d  >= ZigzagDepth=%d は、禁止されている。" , __LINE__,
              ZigzagBackstep,
              ZigzagDepth);
      return NO_SIGNAL;
   }
  
   int mSignal = NO_SIGNAL;
   mSignal = tradeZigzag();




   return mSignal;
}	

int entryZZ_RT(int mTradePattern  // 売買判断ロジック。1:安値が切り上がり中で現在値が、直前の山よりも高いとロング。2:高値切り上げ安値切り上げでロング。
  ) {
   int mSignal = NO_SIGNAL;
   mSignal = tradeZigzag(mTradePattern);



   return mSignal;
}	

//------------------------------------------------------------------
//インジケータ"ZigZag"を使った取引本体。
//入力：マジックナンバー。
//出力：ロングをする時はBUY_SIGNAL、ショートをする時はSELL_SIGNAL、どちらでもない時はNO_SIGNAL
//------------------------------------------------------------------
int tradeZigzag(int mTradePattern  // 売買判断ロジック。1:安値が切り上がり中で現在値が、直前の山よりも高いとロング。2:高値切り上げ安値切り上げでロング。
                ) {
   int sig_entry = NO_SIGNAL;
   global_LastMountORBottom = ZIGZAG_NONE; // 出力値。直前が山か谷か。 

   // Zigzagの山を5件、谷を5件抽出する。返り値は、直近が山なのか谷なのかを示す。
   global_LastMountORBottom = get_ZigZag(1);

   // 山と谷を結ぶ線を描く
   draw_ZigzagLines();


   // メールの本文を、直近が山の時と谷の時でかき分けるためのフラグ。
   MountORBottom_MAIL = global_LastMountORBottom;
 
   if(mTradePattern == 1) {
      // 
      // 1:安値が切り上がり中で現在値が、直前の山よりも高いとロング。
      //
      // ロングエントリー
      // ・直前の山/谷が、谷
      // ・2つ前の谷より直前の谷が、高い。＝安値が切り上がり中
      // ・現在値が、直前の山よりも高い（＝ネックライン（高値）を超えた）ところでロングを実施。→　現在値＝シフト１の終値＝シフト０の始値
      // ・エントリー直後に、直前の谷をストップとする。
      if(global_LastMountORBottom == ZIGZAG_BOTTOM) {
         if(NormalizeDouble(ZigBottom[0], global_Digits) > NormalizeDouble(ZigBottom[1], global_Digits) && ZigBottom[1] > 0.0) {
            if(NormalizeDouble(Close[1], global_Digits) > NormalizeDouble(ZigTop[0], global_Digits) 
                && NormalizeDouble(ZigTop[0], global_Digits) > 0.0) {
               sig_entry = BUY_SIGNAL;
            }
         }
      }
      // ショートエントリー
      // ・直前の山/谷が、山
      // ・2つ前の山より直前の山が低い。＝高値切り下がり中。
      // ・現在値が、直前の谷よりも低い（＝ネックライン（安値）を超えた）ところでショートを実施。→　現在値＝シフト１の終値＝シフト０の始値
      // ・エントリー直後に、直前の山をストップとする。
      else if(global_LastMountORBottom == ZIGZAG_MOUNT) {
         if( NormalizeDouble(ZigTop[0], global_Digits) < NormalizeDouble(ZigTop[1], global_Digits) && ZigTop[0] > 0.0) {
            if(NormalizeDouble(Close[1], global_Digits) < NormalizeDouble(ZigBottom[0], global_Digits) && NormalizeDouble(Close[1], global_Digits) > 0.0) {
               sig_entry = SELL_SIGNAL;
            }
         }
      }
   }
   else if(mTradePattern == 2) {
      // 
      // 2:高値切り上げ安値切り上げでロング。
      //   https://fx-prog.com/ea-zigzag/
      // 
      if(global_LastMountORBottom == ZIGZAG_BOTTOM) {
         if(ZigTop[0] > ZigTop[1] && ZigTop[1] > ZigTop[2] 
            && 
            ZigBottom[0] > ZigBottom[1] && ZigBottom[1] > ZigBottom[2]) {
               sig_entry = BUY_SIGNAL; 
         } 
      }
      else if(global_LastMountORBottom == ZIGZAG_MOUNT) {
         if(ZigTop[0] < ZigTop[1] && ZigTop[1] < ZigTop[2] 
            &&
            ZigBottom[0] < ZigBottom[1] && ZigBottom[1] < ZigBottom[2]) {
               sig_entry = SELL_SIGNAL; 
         }
      }
   }


   return(sig_entry);

}


int tradeZigzag() {
   int sig_entry = NO_SIGNAL;
   global_LastMountORBottom = ZIGZAG_NONE; // 出力値。直前が山か谷か。 

   // Zigzagの山を5件、谷を5件抽出する。返り値は、直近が山なのか谷なのかを示す。
   global_LastMountORBottom = get_ZigZag(1);

   // 山と谷を結ぶ線を描く
   // draw_ZigzagLines();


   // メールの本文を、直近が山の時と谷の時でかき分けるためのフラグ。
   MountORBottom_MAIL = global_LastMountORBottom;
 
   // 
   // ロング/ショート判断
   //
   // ロングエントリー
   // ・直前の山/谷が、谷
   // ・2つ前の谷より直前の谷が、高い。＝安値が切り上がり中
   // ・現在値が、直前の山よりも高い（＝ネックライン（高値）を超えた）ところでロングを実施。→　現在値＝シフト１の終値＝シフト０の始値
   // ・エントリー直後に、直前の谷をストップとする。
   if(global_LastMountORBottom == ZIGZAG_BOTTOM) {
      if(NormalizeDouble(ZigBottom[0], global_Digits) > NormalizeDouble(ZigBottom[1], global_Digits) && ZigBottom[1] > 0.0) {
         if(NormalizeDouble(Close[1], global_Digits) > NormalizeDouble(ZigTop[0], global_Digits) 
             && NormalizeDouble(ZigTop[0], global_Digits) > 0.0) {
            sig_entry = BUY_SIGNAL;
            
         }
      }
   }
   // ショートエントリー
   // ・直前の山/谷が、山
   // ・2つ前の山より直前の山が低い。＝高値切り下がり中。
   // ・現在値が、直前の谷よりも低い（＝ネックライン（安値）を超えた）ところでショートを実施。→　現在値＝シフト１の終値＝シフト０の始値
   // ・エントリー直後に、直前の山をストップとする。
   else if(global_LastMountORBottom == ZIGZAG_MOUNT) {
      if( NormalizeDouble(ZigTop[0], global_Digits) < NormalizeDouble(ZigTop[1], global_Digits) && ZigTop[0] > 0.0) {
         if(NormalizeDouble(Close[1], global_Digits) < NormalizeDouble(ZigBottom[0], global_Digits) && NormalizeDouble(Close[1], global_Digits) > 0.0) {
         /*
printf( "[%d]ZZ SELLシグナル発生。直近は、山" , __LINE__ );
printf( "[%d]ZZ 直近の山%s=%sが更に1つ前の山%s=%sより小さい" , __LINE__, 
         TimeToStr(ZigTopTime[0]), DoubleToStr(ZigTop[0]), 
         TimeToStr(ZigTopTime[1]), DoubleToStr(ZigTop[1])  );
printf( "[%d]ZZ また、現在の値%sが直近の谷%s=%sより小さい" , __LINE__, 
         TimeToStr(Time[0]), DoubleToStr(Close[0]), 
         TimeToStr(ZigBottomTime[0]), DoubleToStr(ZigBottom[0])  );
         */
            sig_entry = SELL_SIGNAL;
         }
      }
   }
   

   //
   //
   // Zigzag以外にゴールデンクロス、デッドクロスを売買シグナル判断に追加した。
   // ・ゴールデンクロスの方が、デッドクロスよりも近ければ、買いシグナルを維持。
   //　・デッドクロスの方が、ゴールデンクロスよりも近ければ、売りシグナルを維持。
   // ・ゴールデンクロス、デッドクロスを計算できなければ、現状維持。（＝Zigzagを優先）
   //
   int lastGC = 0; //直近のゴールデンクロスが発生したシフト
   int lastDC = 0; //直近のデッドクロスが発生したシフト
   bool flag_GCDC = getLastMA_Cross(Period(), // 入力：移動平均を計算するための時間軸
                                    1, // 入力：計算開始位置
                                    lastGC,    // 出力：直近のゴールデンクロスが発生したシフト
                                    lastDC);
   if(flag_GCDC == false) {
      // 何もしない。Zigzagの結果に従う。
   }
   else {
      // sig_entryが、ZigzagでBUY_SIGNALの時
      if(sig_entry == BUY_SIGNAL) {
         //GCの方が近ければ、sig_entryはそのまま（BUY_SIGNAL）。それ以外はNO_SIGNAL
         if(lastGC >= 0 && lastGC < lastDC) {
            // sig_entryは、変更なし
         }
         else {
            // デッドクロスの方が近いので、BUY＿SIGNALは取りやめ
            sig_entry = NO_SIGNAL;
         }
      }
      else if(sig_entry == SELL_SIGNAL) {
         //DCの方が近ければ、sig_entryはそのまま（SELL_SIGNAL）。それ以外はNO_SIGNAL
         if(lastDC >= 0 && lastGC > lastDC) {
            // sig_entryは、変更なし
         }
         else {
            // デッドクロスの方が近いので、BUY＿SIGNALは取りやめ
            sig_entry = NO_SIGNAL;
         }
      }
   }


   //
   //
   // Zigzag以外に1つ長い足で、シフト０，１，２の傾きを売買シグナル判断に追加した。
   // ・傾きが、正ならば、買いシグナルを維持。
   //　・傾きが、負ならば、売りシグナルを維持。
   // ・傾きを計算できなければ、現状維持。（＝Zigzagを優先）
   int currTF   = -1; //　現在の時間軸
   int longerTF = -1; // １つ上の時間軸   
   currTF = getTimeFrameReverse(Period()); //引数にPERIOD_M1を渡せば1, PERIOD_M５を渡せば2を返す。返す範囲は、1～9まで。

   if(currTF >= 9) {  // より上位の時間軸が存在しないため、最大の時間軸PERIOD_MN1とする。
      longerTF = PERIOD_MN1;
   }
   else {                  // 一般的にこの範囲に入り、PERIOD_M1(=1)～PERIOD_W1(=8)である。１を加えて、ENUM_TIMEFRAMESに変換する。
      longerTF = getTimeFrame(currTF + 1);
   }
   // 上記の処理をしても、currTFが0か負は、通常、ありえないため、PERIOD_H1を1つ上の時間軸とする。
   // Zigzagを優先を優先するため、この計算ができなくとも、処理を進める。
   if(currTF <= 0) {       
      longerTF = PERIOD_H1;
   }
   double data[4];  // data[0]=シフト０のclose値、data[1]=シフト1のclose値、data[2]=シフト2のclose値
   int    dataNum = 3;
   ArrayInitialize(data, 0.0);
   double slope     = DOUBLE_VALUE_MIN;
   double intercept = DOUBLE_VALUE_MIN;
   
   data[0] = iClose(global_Symbol, longerTF, 0);
   if(data[0] > 0.0) {
      data[1] = iClose(global_Symbol, longerTF, 1);
      if(data[1] > 0.0) {
         data[2] = iClose(global_Symbol, longerTF, 2);
         if(data[2] > 0.0) {
            // ※ data[0]がx=0、data[1]がx=1というように、data[]にはグラフの左（xが小さい方）から右（xが大きい方）のデータが入っている前提。
            // ※ そのため、シフトのようにxの値が大きいほど過去を意味する場合は、計算後に傾きの正負を反転させる必要あり。
            bool flagResult = calcRegressionLine(data, dataNum, slope, intercept);         
            if(slope > DOUBLE_VALUE_MIN) {
               slope = slope * (-1);
            }
            if(sig_entry == BUY_SIGNAL) {
               if(slope >= 0) {
                  // sig_entryは、変更なし
               } 
               else {
                  sig_entry = NO_SIGNAL;
               }
            }
            else if(sig_entry == SELL_SIGNAL) {
               if(slope <= 0) {
                  // sig_entryは、変更なし
               } 
               else {
                  sig_entry = NO_SIGNAL;
               }
            }
         }
      }
   }

   return(sig_entry);

}

//------------------------------------------------------------------
//インジケータ"ZigZag"の値を200件前まで検索し、山（最大5件）と谷（最大5件）に分けてセットする。
//入力：シフト値
//出力：直前が山ならばZIGZAG_MOUNT、谷ならばZIGZAG_BOTTOMを返す。異常終了時はZIGZAG_NONEを返す。
//------------------------------------------------------------------
int get_ZigZag(int mShift) {
   int i = 0;
   int topCounter = 0;
   int bottomCounter = 0;
   int MountORBottom = ZIGZAG_NONE; // 出力値。直前が山か谷か。 
   ArrayInitialize(ZigTopTime, 0);
   ArrayInitialize(ZigTop, 0.0);   
   ArrayInitialize(ZigBottomTime, 0);
   ArrayInitialize(ZigBottom, 0.0);   
   
   for(i = mShift; i <= mShift + 200; i++) {
      //ZigZagの値を取得
      // iCustom()関数でZigZagの値を取得する時の引数。
      // 1:通貨ペア(NULLで当該通貨)
      // 2:時間軸(0で当該時間軸)
      // 3:インジケータ名称
      // 4:Depthの値（デフォルト設定は12）
      // 5:Deviationの値（デフォルト設定は5）
      // 6:Backstepの値(デフォルト設定は3)
      // 7:取得する値(ZigZagの頂点を取得する場合は0)
      // 8:バーシフト
      double Zg = NormalizeDouble(iCustom(global_Symbol,0,"ZigZag",ZigzagDepth,ZigzagDeviation,ZigzagBackstep,0,i), 5);
   
       
      //ZigZagの値と最高値が同じ場合、頂点なのでZigTopにセット      
      if(Zg != 0 && Zg == NormalizeDouble(High[i], 5) ) {
         // 取得時の直前が山か谷かの判断がついていなければ、山とする。
         if(MountORBottom == ZIGZAG_NONE) {     
            MountORBottom = ZIGZAG_MOUNT; // 直前が山
         }
   
         // 山の値を配列に入れる。最大5つ。
         if(topCounter <= 4) {
            ZigTopTime[topCounter] = Time[i];
            ZigTop[topCounter++] = NormalizeDouble(Zg, global_Digits);
         }
      }
      //ZigZagの値と最安値が同じ場合、底なのでZigBottomにセット            
      if(Zg != 0 && NormalizeDouble(Zg, global_Digits) == NormalizeDouble(Low[i], global_Digits) ) {
         // 取得時の直前が山か谷かの判断がついていなければ、谷とする。
         if(MountORBottom == ZIGZAG_NONE) {     
            MountORBottom = ZIGZAG_BOTTOM; // 直前が谷
         }
   
         // 谷の値を配列に入れる。最大5つ。
         if(bottomCounter <= 4) {
            ZigBottomTime[bottomCounter] = Time[i];
            ZigBottom[bottomCounter++] = NormalizeDouble(Zg, global_Digits);
         }
      }
   
      // 山と谷がどちらか5つ集まったら、処理を中断する。
      if(topCounter > 5 || bottomCounter > 5) {
         break;
      }
   }

   return(MountORBottom);      
}

// Zigzagの山と谷の値を引数で返すバージョン
// グローバル変数への結果セットはしないことに注意
//--------------------------------------------------------------------------
//| Tigris_VirtualTrade.mqhにこの関数をコピーしたget_ZigZagCOPYがあるため、|
//| この関数を修正する時は、あわせてコピー先も修正すること                 |
//-------------------------------------------------------------------------- 
int get_ZigZag(int mShift,
               int mZigzagDepth,
               int mZigzagDeviation,
               int mZigzagBackstep,
               double   &mZigTop[],       //出力：ジグザグの山保存用。ZigTop[0]は最新の高値、ZigTop[1]は1つ前の高値。
               datetime &mZigTopTime[],   //出力：ジグザグの山の時間。
               double   &mZigBottom[],    //出力：ジグザグの谷保存用
               datetime &mZigBottomTime[] //出力：ジグザグの谷保存用
) {
   int i = 0;
   int topCounter = 0;
   int bottomCounter = 0;
   int MountORBottom = ZIGZAG_NONE; // 出力値。直前が山か谷か。 
   ArrayInitialize(mZigTopTime, 0);
   ArrayInitialize(mZigTop, 0.0);   
   ArrayInitialize(mZigBottomTime, 0);
   ArrayInitialize(mZigBottom, 0.0);   
   
   for(i = mShift; i <= mShift + 200; i++) {
      //ZigZagの値を取得
      // iCustom()関数でZigZagの値を取得する時の引数。
      // 1:通貨ペア(NULLで当該通貨)
      // 2:時間軸(0で当該時間軸)
      // 3:インジケータ名称
      // 4:Depthの値（デフォルト設定は12）
      // 5:Deviationの値（デフォルト設定は5）
      // 6:Backstepの値(デフォルト設定は3)
      // 7:取得する値(ZigZagの頂点を取得する場合は0)
      // 8:バーシフト
      double Zg = NormalizeDouble(iCustom(global_Symbol,0,"ZigZag",mZigzagDepth,mZigzagDeviation,mZigzagBackstep,0,i), 5);
   
       
      //ZigZagの値と最高値が同じ場合、頂点なのでZigTopにセット      
      if(Zg != 0 && Zg == NormalizeDouble(High[i], 5) ) {
         // 取得時の直前が山か谷かの判断がついていなければ、山とする。
         if(MountORBottom == ZIGZAG_NONE) {     
            MountORBottom = ZIGZAG_MOUNT; // 直前が山
         }
   
         // 山の値を配列に入れる。最大5つ。
         if(topCounter <= 4) {
            mZigTopTime[topCounter] = Time[i];
            mZigTop[topCounter]     = NormalizeDouble(Zg, global_Digits);;
            topCounter++;
         }
      }
      //ZigZagの値と最安値が同じ場合、底なのでZigBottomにセット            
      if(Zg != 0 && NormalizeDouble(Zg, global_Digits) == NormalizeDouble(Low[i], global_Digits) ) {
         // 取得時の直前が山か谷かの判断がついていなければ、谷とする。
         if(MountORBottom == ZIGZAG_NONE) {     
            MountORBottom = ZIGZAG_BOTTOM; // 直前が谷
         }
   
         // 谷の値を配列に入れる。最大5つ。
         if(bottomCounter <= 4) {
            mZigBottomTime[bottomCounter] = Time[i];
            mZigBottom[bottomCounter]     = NormalizeDouble(Zg, global_Digits);

            topCounter++;            
         }
      }
   
      // 山と谷がどちらか5つ集まったら、処理を中断する。
      if(topCounter > 5 || bottomCounter > 5) {
         break;
      }
   }

   return(MountORBottom);      
}




//------------------------------------------------------------------
//| Zigzagを使った損切値更新ロジックの方が、取引が持つ損切値より有利であれば更新する。。
//| ・2つ前の谷より直前の谷が高ければ、ロングのストップを直前の谷に更新する。
//| ・2つ前の山より直前の山が低ければ、ショートのストップを直前の山に更新する。
//| ただし、以下を前提とする                                                        |
//| ロングエントリー                                                               |
//|・エントリー直後(損切値が0.0)に、直前の谷をストップとする。                                  |
//| ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、
//| 損切値を設定しない。条件を満たす直近の値とした場合は、成績が悪すぎたため。 |
//| ショートエントリー                                                              |
//| ・エントリー直後(損切値が0.0)に、直前の山をストップとする。                                |
//|  ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、
//| 損切値を設定しない。条件を満たす直近の値とした場合は、成績が悪すぎたため。 |
//| 入力：マジックナンバーと通貨ペア。
//| 出力：1件でも失敗すれば、falseを返す。
//------------------------------------------------------------------
bool update_AllOrdersSLZigzag(int    mMagic, 
                             string mSymbol,
                             string mStrategy  // 更新対象とする取引の戦略名。コメント欄に該当する。
                             ) {
   int i = 0;
   int j = 0;
   bool ret = true;
   double long_SL_Cand = 0.0;  // ロングの損切値候補
   double short_SL_Cand = 0.0; // ショートの損切値候補
   int mFlag = -1;             // OederModifyの返り値

   // 直前の山、谷が共に値が無い場合は、ZIGZAGを再計算する。
   if(ZigBottomTime[0] <= 0.0 && ZigTopTime[0] <= 0.0) {  
      global_LastMountORBottom = get_ZigZag(1);
   }


   // 直近がZigzagの谷であれば、ロングの損切値候補を計算する。
   // ただし、2つ前の谷より直前の谷が高い場合とし、直前の谷の値を候補とする。 
   if(ZigBottomTime[0] > ZigTopTime[0]) {  // ZigBottomTime, ZigTopTimeは、datetime型のため、大きい値の方が、より将来。
      global_LastMountORBottom = ZIGZAG_BOTTOM;
   }
   else if(ZigBottomTime[0] < ZigTopTime[0]) {
      global_LastMountORBottom = ZIGZAG_MOUNT;   
   }
   else {
      global_LastMountORBottom = ZIGZAG_NONE;
   }
   
   // 直近がZigzagの山であれば、ショートの損切値候補を計算する。
   // ただし、2つ前の山より直前の山が低い場合とし、直前の山の値を候補とする。 
   if( (global_LastMountORBottom == ZIGZAG_MOUNT) 
        && (NormalizeDouble(ZigTop[0], global_Digits) < NormalizeDouble(ZigTop[1], global_Digits) && ZigBottom[0] > 0.0)) {
         short_SL_Cand = ZigBottom[0];
   }
   // 直近がZigzagの谷であれば、ロングの損切値候補を計算する。
   // ただし、2つ前の谷より直前の谷が大きい場合とし、直前の谷の値を候補とする。 
   else if( (global_LastMountORBottom == ZIGZAG_BOTTOM)
             && (NormalizeDouble(ZigBottom[0], global_Digits) > NormalizeDouble(ZigBottom[1], global_Digits) && ZigBottom[1] > 0.0)) {
         long_SL_Cand = ZigTop[0];
   }
   else {
      ret = false;
   }
/*
   if(long_SL_Cand <= 0.0 && short_SL_Cand <= 0.0) {
      ret = false;   
   }
   // この手前までに問題が発生していたら、以降の処理は行わない。
   if(ret == false) {
      return ret;
   }
*/
   // 口座情報を取得する。
   double mMarketinfoMODE_ASK = MarketInfo(mSymbol,MODE_ASK);
   double mMarketinfoMODE_BID = MarketInfo(mSymbol,MODE_BID);
   double mMarketinfoMODE_POINT = global_Points;
   double mMarketinfoMODE_STOPLEVEL = global_StopLevel;

// printf( "[%d]ZZ update_AllOrdersSLZigzagのループ開始" , __LINE__);
   for(i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
         if(OrderMagicNumber() == mMagic) {
            if(StringCompare(OrderSymbol(),mSymbol) == 0 
               && StringFind(OrderComment(), mStrategy, 0) >= 0) {
               int    mTicket = OrderTicket();
               double mOpen = OrderOpenPrice();
               double mOrderStopLoss   = OrderStopLoss();
               double mOrderTakeProfit = OrderTakeProfit();
               int mBuySell = OrderType();
//printf( "[%d]ZZ %d::チケット番号=%dの損切値更新" , __LINE__,i, mTicket);
    
               // ロングの場合の損切更新
               if(mBuySell == OP_BUY) {
                  // 注目しているOrderが、エントリー直後(損切値が0.0)の時は、
                  // ・エントリー直後(損切値が0.0)に、直前の谷をストップとする。 
                  // ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、直近の値とする。 
                  if(mOrderStopLoss <= 0.0) {
                     // 冒頭で、2つ前の谷より直前の谷が高い場合のみ、ロングのストップを直前の谷を更新候補long_SL_Candにしていれば、その値を設定できるか調べる。
                     /*
                     if(NormalizeDouble(ZigBottom[0], global_Digits) < NormalizeDouble(ZigBottom[1], global_Digits) && ZigBottom[0] > 0.0) {
                        long_SL_Cand = ZigBottom[0];
                     }
                     else if(NormalizeDouble(ZigBottom[1], global_Digits) < NormalizeDouble(ZigBottom[0], global_Digits) && ZigBottom[1] > 0.0) {
                        long_SL_Cand = ZigBottom[1];
                     }
                     */
                     //long_SL_Cand = ZigBottom[0];

                     if(long_SL_Cand > 0.0 
                        &&
                        NormalizeDouble(long_SL_Cand, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // long_SL_Candはそのまま。
                     }
                     else { 
                        // long_SL_Candが制約により設定できないため、制約を満たす直近の谷を探す。
                        // 見つからなければ、設定もれを防ぐため、制約を満たす値を設定する。
                        double buf_long_SL_Cand = DOUBLE_VALUE_MIN;
                        // ロングの場合、直近の谷を損切候補にしている。
                        // 2つめ以降の谷のうち、設定可能な谷があれば、それを損切候補にする。
                        for(j = 0; j < 5; j++) {
                           if(ZigBottom[j] > 0.0 
                              && NormalizeDouble(ZigBottom[j], global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble((1+mMarketinfoMODE_STOPLEVEL) * mMarketinfoMODE_POINT, global_Digits) ){
                              buf_long_SL_Cand = NormalizeDouble(ZigBottom[j], global_Digits);
                           }
                        }
                        if(buf_long_SL_Cand > DOUBLE_VALUE_MIN ) {
                           // 設定可能な次の谷を見つけた。
                           long_SL_Cand = buf_long_SL_Cand;
                        }
                        else {
                           // 設定可能な最小値を損切値に設定していたが、性能が悪すぎた。
                          // 谷から計算される損切値以外は設定しない。
                        }
                     }

                     // ロングではじめて損切設定する際の更新処理
                     if(long_SL_Cand > 0.0
                        && NormalizeDouble(long_SL_Cand, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)
                        ) {
                        mFlag =OrderModify(mTicket, mOpen, long_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_LONG);
                        if(mFlag != true) {
                           printf( "[%d]エラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]エラー mOrderStopLoss=%s  long_SL_Cand=%s " , __LINE__,DoubleToStr(long_SL_Cand), DoubleToStr(mOrderTakeProfit));
                           printf( "[%d]エラー mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                        
                           ret = false;
                        }
                        else {
                        }
                     }                     
                  }
                  
                  // mOrderStopLossが設定済みの場合、
                  // 冒頭で、2つ前の谷より直前の谷が高い場合のみ、ロングのストップを直前の谷を更新候補long_SL_Candにしていれば、
                  // mOrderStopLoss > 0.0 かつ long_SL_Cand > mOrderStopLoss ＝　より有利な損切値であること
                  else if( mOrderStopLoss > 0.0 
                           && long_SL_Cand  > 0.0 
                           && NormalizeDouble(long_SL_Cand, global_Digits) > NormalizeDouble(mOrderStopLoss, global_Digits) ) {
/* printf( "[%d]ZZ update_AllOrdersSLZigzagで、ロングの損切候補変更直前。long_SL_Cand=%s BID=%s ASK=%d STOPLEVEL=%s POINT=%s" , __LINE__,
                DoubleToStr(long_SL_Cand, global_Digits),
                DoubleToStr(mMarketinfoMODE_BID, global_Digits),
                DoubleToStr(mMarketinfoMODE_ASK, global_Digits),
                DoubleToStr(mMarketinfoMODE_STOPLEVEL, global_Digits), 
                DoubleToStr(mMarketinfoMODE_POINT, global_Digits)
                  );*/
                      
                     if(NormalizeDouble(long_SL_Cand, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        mFlag =OrderModify(mTicket, mOpen, long_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_LONG);
                        if(mFlag != true) {
                           printf( "[%d]エラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]エラー mOrderStopLoss=%s  long_SL_Cand=%s " , __LINE__,DoubleToStr(mOrderStopLoss), DoubleToStr(long_SL_Cand));
                           printf( "[%d]エラー mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                           
                           ret = false;
                        }
                     }
                  }
               }// ロングの場合の損切更新
               // ショートの場合の損切更新
               else if(mBuySell == OP_SELL) {
                  // 注目しているOrderが、エントリー直後(損切値が0.0)の時は、
                  //| ・エントリー直後(損切値が0.0)に、直前の山をストップとする。 
                  //|  ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、直近の値とする。
                  if(mOrderStopLoss <= 0.0) {
                     /*
                     if(NormalizeDouble(ZigTop[0], global_Digits) > NormalizeDouble(ZigTop[1], global_Digits) && ZigTop[0] > 0.0) {
                        long_SL_Cand = ZigTop[0];
                     }
                     else if(NormalizeDouble(ZigTop[1], global_Digits) > NormalizeDouble(ZigTop[0], global_Digits) && ZigTop[1] > 0.0) {
                        long_SL_Cand = ZigTop[1];
                     }
                     */
                     //short_SL_Cand = ZigTop[0];
                     // 冒頭で、2つ前の山より直前の山が低い場合のみ、ショートのストップを直前の山を更新候補short_SL_Candにしている。
                     if(NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // short_SL_Candを使って損切値を更新できるので、そのまま。
                        double buf_short_SL_Cand = DOUBLE_VALUE_MIN;
                        // ロングの場合、直近の谷を損切候補にしている。
                        // 2つめ以降の谷のうち、設定可能な谷があれば、それを損切候補にする。
                        for(j = 0; j < 5; j++) {
                           if(ZigTop[j] > 0.0 
                              && NormalizeDouble(ZigTop[j], global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits) ){
                              buf_long_SL_Cand = NormalizeDouble(ZigTop[j], global_Digits);
                           }
                        }
                        if(buf_short_SL_Cand > DOUBLE_VALUE_MIN ) {
                           // 設定可能な次の谷を見つけた。
                           long_SL_Cand = buf_short_SL_Cand;
                        }
                        else {
                           // 設定可能な最小値を損切値に設定していたが、性能が悪すぎた。
                          // 谷から計算される損切値以外は設定しない。
                        }
                        // ショートではじめて損切設定する際の更新処理
                        if(short_SL_Cand > 0.0 
                           &&
                           NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)
                        ) {
                           mFlag =OrderModify(mTicket, mOpen, short_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_SHORT);
                           if(mFlag != true) {
                              printf( "[%d]エラー OrderModify：：%s" , __LINE__,GetLastError());
                              printf( "[%d]エラー mOrderStopLoss=%s  short_SL_Cand=%s " , __LINE__,DoubleToStr(mOrderStopLoss), DoubleToStr(short_SL_Cand));
                              printf( "[%d]エラー mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                              ret = false;
                           }
                        }
                     }
                  }
                  // mOrderStopLossが設定済みの場合、
                  // 冒頭で、2つ前の山より直前の山が低い場合のみ、ショートのストップを直前の山を更新候補short_SL_Candにしている。
                  // mOrderStopLoss > 0.0 かつ 	short_SL_Cand < mOrderStopLoss ＝　より有利な損切値であること
                  else if(mOrderStopLoss > 0.0 
                           && short_SL_Cand > 0.0 
                           && NormalizeDouble(short_SL_Cand, global_Digits) < NormalizeDouble(mOrderStopLoss, global_Digits) ) {

printf( "[%d]ZZ update_AllOrdersSLZigzagで、ショートの損切候補変更直前。変更前=%s  short_SL_Cand=%s BID=%s  ASK=%s STOPLEVEL=%s POINT=%s" , __LINE__,
DoubleToStr(mOrderStopLoss, global_Digits),
DoubleToStr(short_SL_Cand, global_Digits),
DoubleToStr(mMarketinfoMODE_BID, global_Digits),
DoubleToStr(mMarketinfoMODE_ASK, global_Digits),
DoubleToStr(mMarketinfoMODE_STOPLEVEL, global_Digits), 
DoubleToStr(mMarketinfoMODE_POINT, global_Digits),
DoubleToStr(NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits), global_Digits)
);                      
                  
                     if(NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
printf( "[%d]ZZ update_AllOrdersSLZigzagで、ショートの損切変更直前 チケット=%d mOpen=%s SL=%s TP=%s" , __LINE__,
mTicket,
DoubleToStr(mOpen, global_Digits),
DoubleToStr(mOrderStopLoss, global_Digits),
DoubleToStr(mOrderTakeProfit, global_Digits)
);

                        mFlag =OrderModify(mTicket, mOpen, short_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_SHORT);
                        if(mFlag != true) {
                           printf( "[%d]エラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]エラー mOrderStopLoss=%s  short_SL_Cand=%s " , __LINE__,DoubleToStr(mOrderStopLoss), DoubleToStr(short_SL_Cand));
                           printf( "[%d]エラー mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                           ret = false;
                        }
                        else {
                        }
                     }
                  }
                  }
               }
         }
      }
// printf( "[%d]ZZ update_AllOrdersSLZigzagのループ終了" , __LINE__);
   }
   return ret;
}

//
// 関数update_AllOrdersSLZigzagのマジックナンバー無し版
// 精度を高めるため、引数にマジックナンバーのある別版を使うこと
// 
bool update_AllOrdersSLZigzag(string mSymbol,
                              string mStrategy  // 更新対象とする取引の戦略名。コメント欄に該当する。
                             ) {
   int i = 0;
   int j = 0;
   bool ret = true;
   double long_SL_Cand = 0.0;  // ロングの損切値候補
   double short_SL_Cand = 0.0; // ショートの損切値候補
   int mFlag = -1;             // OederModifyの返り値


/*
   printf( "[%d]ZZ update_AllOrdersSLZigzagで、ロングの損切候補と、ショートの損切候補を計算する。" , __LINE__);
   printf( "[%d]ZZ update_AllOrdersSLZigzag。   BID=%s   ASK=%s" , __LINE__,
             DoubleToStr(MarketInfo(mSymbol,MODE_BID), global_Digits),
             DoubleToStr(MarketInfo(mSymbol,MODE_ASK), global_Digits)             
             );
   for(int ii = 0; ii < 5; ii++) {
      printf( "[%d]ZZ ZigTopTime[%d]=%s ZigTop[%d]=%s ZigBottomTime[%d]=%s ZigBottom[%d]=%s" , __LINE__ , 
                 ii, TimeToStr(ZigTopTime[ii]),    ii, DoubleToStr(ZigTop[ii], global_Digits),
                 ii, TimeToStr(ZigBottomTime[ii]), ii, DoubleToStr(ZigBottom[ii], global_Digits));
   }
*/
   // 直近がZigzagの谷であれば、ロングの損切値候補を計算する。
   // ただし、2つ前の谷より直前の谷が高い場合とし、直前の谷の値を候補とする。 
   if(ZigBottomTime[0] > ZigTopTime[0]) {  // ZigBottomTime, ZigTopTimeは、datetime型のため、大きい値の方が、より将来。
      global_LastMountORBottom = ZIGZAG_BOTTOM;
   }
   else if(ZigBottomTime[0] < ZigTopTime[0]) {
      global_LastMountORBottom = ZIGZAG_MOUNT;   
   }
   else {
      global_LastMountORBottom = ZIGZAG_NONE;
   }
   
   // 直近がZigzagの山であれば、ショートの損切値候補を計算する。
   // ただし、2つ前の山より直前の山が低い場合とし、直前の山の値を候補とする。 
   if( (global_LastMountORBottom == ZIGZAG_MOUNT) 
        && (NormalizeDouble(ZigTop[0], global_Digits) < NormalizeDouble(ZigTop[1], global_Digits) && ZigBottom[0] > 0.0)) {
         short_SL_Cand = ZigBottom[0];
   }
   // 直近がZigzagの谷であれば、ロングの損切値候補を計算する。
   // ただし、2つ前の谷より直前の谷が大きい場合とし、直前の谷の値を候補とする。 
   else if( (global_LastMountORBottom == ZIGZAG_BOTTOM)
             && (NormalizeDouble(ZigBottom[0], global_Digits) > NormalizeDouble(ZigBottom[1], global_Digits) && ZigBottom[1] > 0.0)) {
         long_SL_Cand = ZigTop[0];
   }
   else {
      ret = false;
   }
/*
   if(long_SL_Cand <= 0.0 && short_SL_Cand <= 0.0) {
      ret = false;   
   }
   // この手前までに問題が発生していたら、以降の処理は行わない。
   if(ret == false) {
      return ret;
   }
*/
   // 口座情報を取得する。
   double mMarketinfoMODE_ASK = MarketInfo(mSymbol,MODE_ASK);
   double mMarketinfoMODE_BID = MarketInfo(mSymbol,MODE_BID);
   double mMarketinfoMODE_POINT = global_Points;
   double mMarketinfoMODE_STOPLEVEL = global_StopLevel;

// printf( "[%d]ZZ update_AllOrdersSLZigzagのループ開始" , __LINE__);
   for(i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
            if(StringCompare(OrderSymbol(),mSymbol) == 0 
               && StringFind(OrderComment(), mStrategy, 0) >= 0) {
               int    mTicket = OrderTicket();
               double mOpen = OrderOpenPrice();
               double mOrderStopLoss   = OrderStopLoss();
               double mOrderTakeProfit = OrderTakeProfit();
               int mBuySell = OrderType();
//printf( "[%d]ZZ %d::チケット番号=%dの損切値更新" , __LINE__,i, mTicket);
    
               // ロングの場合の損切更新
               if(mBuySell == OP_BUY) {
                  // 注目しているOrderが、エントリー直後(損切値が0.0)の時は、
                  // ・エントリー直後(損切値が0.0)に、直前の谷をストップとする。 
                  // ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、直近の値とする。 
                  if(mOrderStopLoss <= 0.0) {
                     // 冒頭で、2つ前の谷より直前の谷が高い場合のみ、ロングのストップを直前の谷を更新候補long_SL_Candにしていれば、その値を設定できるか調べる。
                     /*
                     if(NormalizeDouble(ZigBottom[0], global_Digits) < NormalizeDouble(ZigBottom[1], global_Digits) && ZigBottom[0] > 0.0) {
                        long_SL_Cand = ZigBottom[0];
                     }
                     else if(NormalizeDouble(ZigBottom[1], global_Digits) < NormalizeDouble(ZigBottom[0], global_Digits) && ZigBottom[1] > 0.0) {
                        long_SL_Cand = ZigBottom[1];
                     }
                     */
                     //long_SL_Cand = ZigBottom[0];

                     if(long_SL_Cand > 0.0 
                        &&
                        NormalizeDouble(long_SL_Cand, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // long_SL_Candはそのまま。
                     }
                     else { 
                        // long_SL_Candが制約により設定できないため、制約を満たす直近の谷を探す。
                        // 見つからなければ、設定もれを防ぐため、制約を満たす値を設定する。
                        double buf_long_SL_Cand = DOUBLE_VALUE_MIN;
                        // ロングの場合、直近の谷を損切候補にしている。
                        // 2つめ以降の谷のうち、設定可能な谷があれば、それを損切候補にする。
                        for(j = 0; j < 5; j++) {
                           if(ZigBottom[j] > 0.0 
                              && NormalizeDouble(ZigBottom[j], global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble((1+mMarketinfoMODE_STOPLEVEL) * mMarketinfoMODE_POINT, global_Digits) ){
                              buf_long_SL_Cand = NormalizeDouble(ZigBottom[j], global_Digits);
                           }
                        }
                        if(buf_long_SL_Cand > DOUBLE_VALUE_MIN ) {
                           // 設定可能な次の谷を見つけた。
                           long_SL_Cand = buf_long_SL_Cand;
                        }
                        else {
                           // 設定可能な最小値を損切値に設定していたが、性能が悪すぎた。
                          // 谷から計算される損切値以外は設定しない。
                        }
                     }

                     // ロングではじめて損切設定する際の更新処理
                     if(long_SL_Cand > 0.0
                        && NormalizeDouble(long_SL_Cand, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)
                        ) {
                        mFlag =OrderModify(mTicket, mOpen, long_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_LONG);
                        if(mFlag != true) {
                           printf( "[%d]エラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]エラー mOrderStopLoss=%s  long_SL_Cand=%s " , __LINE__,DoubleToStr(long_SL_Cand), DoubleToStr(mOrderTakeProfit));
                           printf( "[%d]エラー mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                        
                           ret = false;
                        }
                        else {
                        }
                     }                     
                  }
                  
                  // mOrderStopLossが設定済みの場合、
                  // 冒頭で、2つ前の谷より直前の谷が高い場合のみ、ロングのストップを直前の谷を更新候補long_SL_Candにしていれば、
                  // mOrderStopLoss > 0.0 かつ long_SL_Cand > mOrderStopLoss ＝　より有利な損切値であること
                  else if( mOrderStopLoss > 0.0 
                           && long_SL_Cand  > 0.0 
                           && NormalizeDouble(long_SL_Cand, global_Digits) > NormalizeDouble(mOrderStopLoss, global_Digits) ) {
/* printf( "[%d]ZZ update_AllOrdersSLZigzagで、ロングの損切候補変更直前。long_SL_Cand=%s BID=%s ASK=%d STOPLEVEL=%s POINT=%s" , __LINE__,
                DoubleToStr(long_SL_Cand, global_Digits),
                DoubleToStr(mMarketinfoMODE_BID, global_Digits),
                DoubleToStr(mMarketinfoMODE_ASK, global_Digits),
                DoubleToStr(mMarketinfoMODE_STOPLEVEL, global_Digits), 
                DoubleToStr(mMarketinfoMODE_POINT, global_Digits)
                  );*/
                      
                     if(NormalizeDouble(long_SL_Cand, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        mFlag =OrderModify(mTicket, mOpen, long_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_LONG);
                        if(mFlag != true) {
                           printf( "[%d]エラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]エラー mOrderStopLoss=%s  long_SL_Cand=%s " , __LINE__,DoubleToStr(mOrderStopLoss), DoubleToStr(long_SL_Cand));
                           printf( "[%d]エラー mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                           
                           ret = false;
                        }
                     }
                  }
               }// ロングの場合の損切更新
               // ショートの場合の損切更新
               else if(mBuySell == OP_SELL) {
                  // 注目しているOrderが、エントリー直後(損切値が0.0)の時は、
                  //| ・エントリー直後(損切値が0.0)に、直前の山をストップとする。 
                  //|  ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、直近の値とする。
                  if(mOrderStopLoss <= 0.0) {
                     /*
                     if(NormalizeDouble(ZigTop[0], global_Digits) > NormalizeDouble(ZigTop[1], global_Digits) && ZigTop[0] > 0.0) {
                        long_SL_Cand = ZigTop[0];
                     }
                     else if(NormalizeDouble(ZigTop[1], global_Digits) > NormalizeDouble(ZigTop[0], global_Digits) && ZigTop[1] > 0.0) {
                        long_SL_Cand = ZigTop[1];
                     }
                     */
                     //short_SL_Cand = ZigTop[0];
                     // 冒頭で、2つ前の山より直前の山が低い場合のみ、ショートのストップを直前の山を更新候補short_SL_Candにしている。
                     if(NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // short_SL_Candを使って損切値を更新できるので、そのまま。
                        double buf_short_SL_Cand = DOUBLE_VALUE_MIN;
                        // ロングの場合、直近の谷を損切候補にしている。
                        // 2つめ以降の谷のうち、設定可能な谷があれば、それを損切候補にする。
                        for(j = 0; j < 5; j++) {
                           if(ZigTop[j] > 0.0 
                              && NormalizeDouble(ZigTop[j], global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits) ){
                              buf_long_SL_Cand = NormalizeDouble(ZigTop[j], global_Digits);
                           }
                        }
                        if(buf_short_SL_Cand > DOUBLE_VALUE_MIN ) {
                           // 設定可能な次の谷を見つけた。
                           long_SL_Cand = buf_short_SL_Cand;
                        }
                        else {
                           // 設定可能な最小値を損切値に設定していたが、性能が悪すぎた。
                          // 谷から計算される損切値以外は設定しない。
                        }
                        // ショートではじめて損切設定する際の更新処理
                        if(short_SL_Cand > 0.0 
                           &&
                           NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)
                        ) {
                           mFlag =OrderModify(mTicket, mOpen, short_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_SHORT);
                           if(mFlag != true) {
                              printf( "[%d]エラー OrderModify：：%s" , __LINE__,GetLastError());
                              printf( "[%d]エラー mOrderStopLoss=%s  short_SL_Cand=%s " , __LINE__,DoubleToStr(mOrderStopLoss), DoubleToStr(short_SL_Cand));
                              printf( "[%d]エラー mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                              ret = false;
                           }
                        }
                     }
                  }
                  // mOrderStopLossが設定済みの場合、
                  // 冒頭で、2つ前の山より直前の山が低い場合のみ、ショートのストップを直前の山を更新候補short_SL_Candにしている。
                  // mOrderStopLoss > 0.0 かつ 	short_SL_Cand < mOrderStopLoss ＝　より有利な損切値であること
                  else if(mOrderStopLoss > 0.0 
                           && short_SL_Cand > 0.0 
                           && NormalizeDouble(short_SL_Cand, global_Digits) < NormalizeDouble(mOrderStopLoss, global_Digits) ) {

printf( "[%d]ZZ update_AllOrdersSLZigzagで、ショートの損切候補変更直前。変更前=%s  short_SL_Cand=%s BID=%s  ASK=%s STOPLEVEL=%s POINT=%s" , __LINE__,
DoubleToStr(mOrderStopLoss, global_Digits),
DoubleToStr(short_SL_Cand, global_Digits),
DoubleToStr(mMarketinfoMODE_BID, global_Digits),
DoubleToStr(mMarketinfoMODE_ASK, global_Digits),
DoubleToStr(mMarketinfoMODE_STOPLEVEL, global_Digits), 
DoubleToStr(mMarketinfoMODE_POINT, global_Digits),
DoubleToStr(NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits), global_Digits)
);                      
                  
                     if(NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
printf( "[%d]ZZ update_AllOrdersSLZigzagで、ショートの損切変更直前 チケット=%d mOpen=%s SL=%s TP=%s" , __LINE__,
mTicket,
DoubleToStr(mOpen, global_Digits),
DoubleToStr(mOrderStopLoss, global_Digits),
DoubleToStr(mOrderTakeProfit, global_Digits)
);

                        mFlag =OrderModify(mTicket, mOpen, short_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_SHORT);
                        if(mFlag != true) {
                           printf( "[%d]エラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]エラー mOrderStopLoss=%s  short_SL_Cand=%s " , __LINE__,DoubleToStr(mOrderStopLoss), DoubleToStr(short_SL_Cand));
                           printf( "[%d]エラー mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                           ret = false;
                        }
                        else {
                        }
                     }
                  }
               }
            }
      }
   }
   return ret;
}




void draw_ZigzagLines() {

   ObjectDelete("FirstLine");
   ObjectDelete("SecondLine");
   ObjectDelete("ThirdLine");

   if(global_LastMountORBottom == ZIGZAG_BOTTOM) {
/*
   printf("[%d]ZZ 直近は、谷>%d<" , __LINE__ , global_LastMountORBottom);
   for(int jj = 0; jj < 5; jj++) {
      printf( "[%d]ZZ ZigTopTime[%d]=%s ZigTop[%d]=%s ZigBottomTime[%d]=%s ZigBottom[%d]=%s" , __LINE__ , 
                 jj, TimeToStr(ZigTopTime[jj]),    jj, DoubleToStr(ZigTop[jj], global_Digits),
                 jj, TimeToStr(ZigBottomTime[jj]), jj, DoubleToStr(ZigBottom[jj], global_Digits));
   }
   */   
      ObjectDelete("FirstLine");
      ObjectCreate("FirstLine", OBJ_TREND,0, ZigBottomTime[0], ZigBottom[0], ZigTopTime[0],    ZigTop[0],    ZigTopTime[0],    ZigTop[0]);
      ObjectSet("FirstLine",OBJPROP_COLOR, clrYellow);
      ObjectSet("FirstLine",OBJPROP_WIDTH,3);
      ObjectSet("FirstLine", OBJPROP_STYLE, STYLE_DOT);   
     
      ObjectDelete("SecondLine");
      ObjectCreate("SecondLine",OBJ_TREND,0, ZigTopTime[0],    ZigTop[0],    ZigBottomTime[1], ZigBottom[1], ZigBottomTime[1], ZigBottom[1]);
      ObjectSet("SecondLine",OBJPROP_COLOR,clrYellow);
      ObjectSet("SecondLine",OBJPROP_WIDTH,3);
      ObjectSet("SecondLine", OBJPROP_STYLE, STYLE_DOT);     
   
      ObjectDelete("ThirdLine");
      ObjectCreate("ThirdLine",OBJ_TREND,0,  ZigBottomTime[1], ZigBottom[1], ZigTopTime[1],    ZigTop[1],    ZigBottom[1],     ZigTopTime[1]);
      ObjectSet("ThirdLine",OBJPROP_COLOR,clrYellow);
      ObjectSet("ThirdLine",OBJPROP_WIDTH,3);
      ObjectSet("ThirdLine", OBJPROP_STYLE, STYLE_DOT);        
   }
   else if(global_LastMountORBottom == ZIGZAG_MOUNT) {
/*
   printf( "[%d]ZZ 直近は、山>%d<" , __LINE__ , global_LastMountORBottom);
   for(int ii = 0; ii < 5; ii++) {
      printf( "[%d]ZZ ZigTopTime[%d]=%s ZigTop[%d]=%s ZigBottomTime[%d]=%s ZigBottom[%d]=%s" , __LINE__ , 
                 ii, TimeToStr(ZigTopTime[ii]),    ii, DoubleToStr(ZigTop[ii], global_Digits),
                 ii, TimeToStr(ZigBottomTime[ii]), ii, DoubleToStr(ZigBottom[ii], global_Digits));
   }
*/   
      ObjectDelete("FirstLine");
      ObjectCreate("FirstLine",OBJ_TREND,0, ZigTopTime[0], ZigTop[0], ZigBottomTime[0], ZigBottom[0]);
      ObjectSet("FirstLine",OBJPROP_COLOR,clrLime);
      ObjectSet("FirstLine",OBJPROP_WIDTH,3);
      ObjectSet("FirstLine", OBJPROP_STYLE, STYLE_DOT);
      ObjectDelete("SecondLine");
      ObjectCreate("SecondLine",OBJ_TREND,0, ZigBottomTime[0], ZigBottom[0],ZigTopTime[1], ZigTop[1]);
      ObjectSet("SecondLine",OBJPROP_COLOR,clrLime);
      ObjectSet("SecondLine",OBJPROP_WIDTH,3);
      ObjectSet("SecondLine", OBJPROP_STYLE, STYLE_DOT);   
      ObjectDelete("ThirdLine");
      ObjectCreate("ThirdLine",OBJ_TREND,0,ZigTopTime[1], ZigTop[1], ZigBottomTime[1], ZigBottom[1]);
      ObjectSet("ThirdLine",OBJPROP_COLOR,clrLime);
      ObjectSet("ThirdLine",OBJPROP_WIDTH,3);
      ObjectSet("ThirdLine", OBJPROP_STYLE, STYLE_DOT);   
   
   }
   else {
      printf( "[%d]ZZ 直近は、どちらでもなし>%d<" , __LINE__,global_LastMountORBottom );
   }
}






//・ロングは、Close[1]が直前の山を上回った時に損切値更新を実施。
//　ショートは、Close[1]が直前の谷を下回った時に実施
//・TP,SLが共に0の時、zigzagの山と谷を使った損切設定を試みる
//　ZZFlooring関数は次のとおり。
//　直近の谷がその1つ前の谷を上回り、Close[1]が直前の山を上回れば、ロングの損切を直近の谷にすることを試みる。
//　- ただし、更新を試みる損切候補が、ストップレベルから計算した最大損切可能値を下回り、設定済み損切値より有利である（上回る）こと。
//
//　直近の山がその1つ前の山を下回り、Close[1]が直前の谷を下回れば、ショートの損切を直近の山にすることを試みる。
//　- ただし、更新を試みる損切候補が、ストップレベルから計算した最小損切可能値を上回り、設定済み損切値より有利である（下回る）こと。
bool ZZTrailing(string mSymbol,
                  int    mMagic   // flooring設定をする約定のマジックナンバー
                ) {
   double shortSL_Cand = DOUBLE_VALUE_MIN; // ショート損切候補値
   double longSL_Cand  = DOUBLE_VALUE_MIN; // ロング損切候補値
   // int lastMountBottom = get_ZigZag(1)を使い、ZigTop、ZigTopTime、ZigBottom、ZigBottomTimeを計算する。
   int lastMountBottom = get_ZigZag(1);
   if(lastMountBottom != ZIGZAG_MOUNT && lastMountBottom != ZIGZAG_BOTTOM) {
printf( "[%d]ZZ " , __LINE__);
      return false;
   }
   if(ZigTop[0] <= 0.0 ||  ZigTop[1] <= 0.0 || ZigBottom[0] <= 0.0 || ZigBottom[1] <= 0.0) {
printf( "[%d]ZZ " , __LINE__);
      return false;
   }
   // lastMountBottom == ZIGZAG_MOUNTの時は、下降中であるから、ショートの損切更新候補を計算する。
   if(lastMountBottom == ZIGZAG_MOUNT) {
      // ZigTop[0] < ZigTop[1] つまり、直前の山がその1つ前の山を下回っていること
      if(NormalizeDouble(ZigTop[0], global_Digits) < NormalizeDouble(ZigTop[1], global_Digits)) {
         // Close[1] < ZigBottom[0] つまり、終値が直前の谷を下回っていること
         if(NormalizeDouble(Close[1], global_Digits) < NormalizeDouble(ZigBottom[0], global_Digits)) {
            // ショートの損切候補値を直前の山の値とする。
            shortSL_Cand = ZigTop[0];
         }
      }
   }
   // lastMountBottom == ZIGZAG_BOTTOMの時は、上昇中であるから、ロングの損切更新候補を計算する。
   else if(lastMountBottom == ZIGZAG_BOTTOM) {
      // ZigBottom[0] > ZigBottom[1]つまり、直前の谷がその1つ前の谷を上回っていること
      if(NormalizeDouble(ZigBottom[0], global_Digits) > NormalizeDouble(ZigBottom[1], global_Digits)) {
         // Close[1] > Zigtop[0]つまり、終値が直前の山を上回っていること
         if(NormalizeDouble(Close[1], global_Digits) > NormalizeDouble(ZigTop[0], global_Digits)) {
            // ロングの損切候補地を直前の谷の値とする。
            longSL_Cand = ZigBottom[0];
         }
      }
   }

   // 損切候補がどちらも設定されていなければ以降の処理はしない。
   if(shortSL_Cand <= 0.0 && longSL_Cand <= 0.0) {
      return false;
   }
   int mBUYSELL;
   double mTP;
   double mSL;
   double mOpen;
   double minimalSL;
   double maxmalSL;
   double mMarketinfoMODE_BID = MarketInfo(mSymbol,MODE_BID);     
   double mMarketinfoMODE_ASK = MarketInfo(mSymbol,MODE_ASK);  
   ulong mOrderTicket;
   double mMarketinfoMODE_STOPLEVEL = change_PiPS2Point(global_StopLevel);    
   bool   mFlag;
   //double bufSL;
   // shortSL_Cand > 0.0 || longSL_Cand > 0.0つまり、損切候補がどちらか設定されていれば、オープン中の取引に対して、損切値更新を試みる
   for(int i = OrdersTotal() - 1; i >= 0;i--) {						
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == true 
         && (mMagic == OrderMagicNumber())  
         && (StringLen(mSymbol) > 0 && StringCompare(mSymbol, OrderSymbol()) ) == 0 
           ) {
         mBUYSELL = OrderType();	
         if( mBUYSELL == OP_BUY || mBUYSELL == OP_SELL) {
            mSL          = OrderStopLoss();
            mOpen        = OrderOpenPrice();
         }
         double diffTPSL = MathAbs(mTP - mSL);
         double newTP    = 0;

         // 着目した取引がショートの場合の損切更新
         if(mBUYSELL == OP_SELL) {
            if(shortSL_Cand > 0.0
                 &&
               shortSL_Cand <= mOpen 
                 &&
               (mSL <= 0.0 || (mSL > 0.0 && shortSL_Cand <= mSL))  
               ) {  // shortSL_Candが事前に入手されており、損切しても利益が出る値であること。かつ、損切設定mSLが設定されていればより有利であること。

               // ショートの損切は、その時のASK+ストップレベルより大きくなくてはならない。
               // 参考資料：https://toushi-strategy.com/mt4/stoplevel/　　から、推測。
               minimalSL = NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL, global_Digits);

               
               if( shortSL_Cand > minimalSL) {
                  // 更新可能な損切候補であれば、更新する。
                  mOrderTicket = OrderTicket();
                  mTP = OrderTakeProfit();
                  // mTPが設定されていれば、shortSL_Candから変更前のmTPとmSLの差額と同じポイントに移動する。
                  if(mTP > 0.0) {
                     mTP = shortSL_Cand - diffTPSL;
                  }
                  
                  mFlag =OrderModify(mOrderTicket,mOpen, shortSL_Cand, mTP, 0, LINE_COLOR_SHORT);	
                  if(mFlag != true) {
                     printf( "[%d]ZZエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                     printf( "[%d]ZZエラー 修正前のTP=%s SL=%s  修正しようとしたSL=%s  オープンプライス=%s ASK=%s" , __LINE__, 
                           DoubleToStr(mSL, 5),
                           DoubleToStr(shortSL_Cand, 5),
                           DoubleToStr(mOpen, 5),
                           DoubleToStr(mMarketinfoMODE_ASK, 5)
                     );
                  }  
               }
            }
         }
         // 着目した取引がロングの場合の損切更新
         else if(mBUYSELL == OP_BUY) {
            if(longSL_Cand > 0.0
                 && 
               longSL_Cand >= mOpen 
                 &&
               (mSL <= 0.0 || (mSL > 0.0 && longSL_Cand >= mSL))  
               ) {  // longSL_Candが事前に入手されており、損切しても利益が出る値であること。かつ、損切設定mSLが設定されていればより有利であること。

               // ロングの損切は、その時のBID-ストップレベルより小さくなくてはならない。
               // 参考資料：https://toushi-strategy.com/mt4/stoplevel/
               maxmalSL = NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL, global_Digits);
printf( "[%d]ZZ ロング損切候補=%s　　設定できる最大値は=%s" , __LINE__,
DoubleToStr(longSL_Cand, 5),
DoubleToStr(maxmalSL, 5)
);

               if( longSL_Cand < minimalSL) {
                  // 更新可能な損切候補であれば、更新する。
                  mOrderTicket = OrderTicket();
                  mTP = OrderTakeProfit();
                  // mTPが設定されていれば、shortSL_Candから変更前のmTPとmSLの差額と同じポイントに移動する。
                  if(mTP > 0.0) {
                     mTP = shortSL_Cand + diffTPSL;
                  }
                  
                  mFlag =OrderModify(mOrderTicket, mOpen, longSL_Cand, newTP, 0, LINE_COLOR_LONG);
                  if(mFlag != true) {
                     printf( "[%d]ZZエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                     printf( "[%d]ZZエラー 修正前のSL=%s  修正しようとしたSL=%s  オープンプライス=%s ASK=%s" , __LINE__, 
                           DoubleToStr(mSL, 5),
                           DoubleToStr(shortSL_Cand, 5),
                           DoubleToStr(mOpen, 5),
                           DoubleToStr(mMarketinfoMODE_ASK, 5)
                     );
                     
                  }  
               }
            }
         }
      }
   } 
   return true;
}

