/*
  ロング　：直前が谷。これを、買いフラクタル（下向き）とする。
            Close1, Close2が直前の山を結ぶ線をうわ抜けて、トレンドを上にブレイクした時。
　　　　　　直前の谷である買いフラクタル（下向き）が、アリゲータの歯より上であること。
　ショート：直前が山。これを、売りフラクタル（上向き）とする。
　　　　　　Close1, Close2が直前の谷を結ぶ線を下抜けて、トレンドを下にブレイクした時
　　　　　　直前の山である売りフラクタル（上向き）が、アリゲータの歯より下であること。

         // フラクタルとTEETHの位置関係
         //
         // https://www.metatrader5.com/ja/terminal/help/indicators/bw_indicators/fractals
         // フラクタルシグナルはアリゲーターでろ過する必要があります。
         // つまり、フラクタルがアリゲーターの歯線よりも低い場合の買いの決済と、
         // フラクタルがアリゲーターの歯線よりも高い場合の売りの決済は控えるべきです。
         // 
         // https://jforexmaster.com/billwilliams-fractals-alligator/
         // TEETHの上に買いフラクタル（下向き）があれば、買い注文をフラクタルの頂点から1.2pips上乗せして発注。（ASK）←買いフラクタル（下向き）＝直近の谷
         // TEETHの下に売りフラクタル（上向き）があれば、売り注文をフラクタルの頂点から1.2pips上乗せして発注。（BID）←売りフラクタル（上向き）＝直近の山
         // TEETHの上に売りフラクタル（上向き）があってもトレードしない。
         // TEETHの下に買いフラクタル（下向き）があってもトレードしない。

*/
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
//#include <Tigris_VirtualTrade.mqh>


//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	




//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
/*
int FRACTALSPAN   = 200;// この値はフラクタルの山と谷を各２つずつ探すために使う。いくつのシフトをさかのぼってフラクタルの山と谷を探すか。;
int FRACTALADX    = 25; // 逆張りをする時、ADXがいくつ未満であれば、トレンドが弱いと判断するか。→　成績が悪いため、逆張りはせず、シグナルを取り消すのみ。
int FRACTALMETHOD = 1;  // 1:フラクタルのみ、2:アリゲーターによるトレンド追加。3:直近のフラクタルを結んだ線の傾きを判断。
*/



// 関数get_BuySellSig_FRACvals() 内で計算した後、損切値設定に使うため、グローバル変数とした。
/*
double Fractals_UPPER1_y = 0.0;    //直近のフラクタル値(UPPER)
int    Fractals_UPPER1_x = 0;      //直近のフラクタル値(UPPER)のシフト値
datetime Fractals_UPPER1_time = 0; // フラクタルを取得したシフト値のTime

double Fractals_UPPER2_y = 0.0;    //2つ目のフラクタル値(UPPER)
int    Fractals_UPPER2_x = 0;      //2つ目のフラクタル値(UPPER)のシフト値
datetime Fractals_UPPER2_time = 0; // フラクタルを取得したシフト値のTime

double Fractals_UPPER3_y = 0.0;    //2つ目のフラクタル値(UPPER)
int    Fractals_UPPER3_x = 0;      //2つ目のフラクタル値(UPPER)のシフト値
datetime Fractals_UPPER3_time = 0; // フラクタルを取得したシフト値のTime

double Fractals_LOWER1_y = 0.0;    //直近のフラクタル値(LOWER)
int    Fractals_LOWER1_x = 0;      //直近のフラクタル値(LOWER)のシフト値
datetime Fractals_LOWER1_time = 0; // フラクタルを取得したシフト値のTime

double Fractals_LOWER2_y = 0.0;  //2つ目のフラクタル値(LOWER)
int    Fractals_LOWER2_x = 0;  //2つ目のフラクタル値(LOWER)のシフト値
datetime Fractals_LOWER2_time = 0; // フラクタルを取得したシフト値のTime   

double Fractals_LOWER3_y = 0.0;  //2つ目のフラクタル値(LOWER)
int    Fractals_LOWER3_x = 0;  //2つ目のフラクタル値(LOWER)のシフト値
datetime Fractals_LOWER3_time = 0; // フラクタルを取得したシフト値のTime   
*/
/*
https://fx-tradesite.com/fractal-indicator-4848
フラクタルインジケーターとは、高値安値を定義したインジケーター。
5本のローソク足を比べて
3本目の高値が最も高い場合「Fractal up」
3本目の安値が最も小さい時「Fractal down」
が表示。
直近5本で真ん中が最も高い、安い時にサインが表示されるイメージ。
これにより高値安値を定義づけ。
*/

extern bool TEST_CALC_SLOPE_BY3 = false; // 実験用の外部パラメータ。売買判断時の山・谷を結ぶ直線を直前3つから計算する時にtrue
//+------------------------------------------------------------------+
//|01.フラクタルFrac                                 　　　　　      |
//+------------------------------------------------------------------+
// フラクタルを使った売買シグナルを作成する本体（＝出発点）
int entryWithFrac() {
   st_Fractal m_st_Fractals[FRAC_NUMBER];
   return entryWithFrac(m_st_Fractals);
}


int entryWithFrac(st_Fractal &m_st_Fractals[]  // 出力用。売買シグナルを作成する過程で作成したフラクタル値を返す。
                  ) {

   // 「トレンド相場では非常に 強いフラクタルですが、レンジではだましが連発」のため、
   // トレンドが発生していない場合は、NO_SIGNALを返す。
   int trendAlligator = get_Trend_Alligator(global_Symbol, 
                                            global_Period,
                                            1);
   if(trendAlligator == NoTrend) {
//printf( "[%d]FRAC trendAlligatorによるトレンド無しのため、シグナル無し　　通貨ペア=%s  時間軸=%d" , __LINE__,global_Symbol, global_Period);
   
      return NO_SIGNAL;
   }

   // フラクタルの値を取得し、構造体st_Fractalsに入れる。
   bool flag_getFrac = get_Fractals(m_st_Fractals);
   if(flag_getFrac == false) {
      return NO_SIGNAL;
   }

   // フラクタルを使った売買判断をする。
   int entry_sig = get_BuySellSig_FRACvals(m_st_Fractals);
   
   return entry_sig;
}




//************************************************
//************************************************


//フラクタルを使った売買判断
// BUY_SIGNAL, SELL_SIGNAL, NO_SIGNALのいずれかを返す。
// 他の関数から呼び出すことを考えて、入力用引数は持たない。
// この関数内で計算したフラクタル山２つ、谷２つを引数に渡す。
int get_BuySellSig_FRACvals(st_Fractal &m_st_Fractals[]) {
   int ret = NO_SIGNAL;
double mFractals_UPPER1_y = 0.0;    //直近のフラクタル値(UPPER)
int    mFractals_UPPER1_x = 0;      //直近のフラクタル値(UPPER)のシフト値
datetime mFractals_UPPER1_time = 0; // フラクタルを取得したシフト値のTime

double mFractals_UPPER2_y = 0.0;    //2つ目のフラクタル値(UPPER)
int    mFractals_UPPER2_x = 0;      //2つ目のフラクタル値(UPPER)のシフト値
datetime mFractals_UPPER2_time = 0; // フラクタルを取得したシフト値のTime

double mFractals_UPPER3_y = 0.0;    //2つ目のフラクタル値(UPPER)
int    mFractals_UPPER3_x = 0;      //2つ目のフラクタル値(UPPER)のシフト値
datetime mFractals_UPPER3_time = 0; // フラクタルを取得したシフト値のTime

double mFractals_LOWER1_y = 0.0;    //直近のフラクタル値(LOWER)
int    mFractals_LOWER1_x = 0;      //直近のフラクタル値(LOWER)のシフト値
datetime mFractals_LOWER1_time = 0; // フラクタルを取得したシフト値のTime

double mFractals_LOWER2_y = 0.0;  //2つ目のフラクタル値(LOWER)
int    mFractals_LOWER2_x = 0;  //2つ目のフラクタル値(LOWER)のシフト値
datetime mFractals_LOWER2_time = 0; // フラクタルを取得したシフト値のTime   

double mFractals_LOWER3_y = 0.0;  //2つ目のフラクタル値(LOWER)
int    mFractals_LOWER3_x = 0;  //2つ目のフラクタル値(LOWER)のシフト値
datetime mFractals_LOWER3_time = 0; // フラクタルを取得したシフト値のTime   

   // 初期化
   double fracSignal_UPPER_Shift2 = 0.0; // (Fractals_UPPER1_x, Fractals_UPPER1_y)と(Fractals_UPPER2_x, Fractals_UPPER2_y)
                                         // を結ぶ直線を想定したときの、x軸2(=シフト2)の時のy軸（フラクタル値）の値
   double fracSignal_UPPER_Shift1  = 0.0; // (Fractals_UPPER1_x, Fractals_UPPER1_y)と(Fractals_UPPER2_x, Fractals_UPPER2_y)
                                         // を結ぶ直線を想定したときの、x軸1(=シフト1)の時のy軸（フラクタル値）の値
   double fracSignal_UPPER_slope  = 0.0; // (Fractals_UPPER1_x, Fractals_UPPER1_y)と(Fractals_UPPER2_x, Fractals_UPPER2_y)
                                         // を結ぶ直線を想定したときの傾き
   double fracSignal_UPPER_intercept = 0.0; // (Fractals_UPPER1_x, Fractals_UPPER1_y)と(Fractals_UPPER2_x, Fractals_UPPER2_y)
                                            // を結ぶ直線を想定したときの傾き
   double fracSignal_LOWER_Shift2 = 0.0; // (Fractals_LOWER1_x, Fractals_LOWER1_y)と(Fractals_LOWER2_x, Fractals_LOWER2_y)
                                         // を結ぶ直線を想定したときの、x軸2(=シフト2)のy軸（フラクタル値）の値
   double fracSignal_LOWER_Shift1  = 0.0; // (Fractals_LOWER1_x, Fractals_LOWER1_y)と(Fractals_LOWER2_x, Fractals_LOWER2_y)
                                         // を結ぶ直線を想定したときの、x軸1(=シフト1)のy軸（フラクタル値）の値
   double fracSignal_LOWER_slope  = 0.0; // (Fractals_UPPER1_x, Fractals_UPPER1_y)と(Fractals_UPPER2_x, Fractals_UPPER2_y)
                                         // を結ぶ直線を想定したときの傾き                                         
   double fracSignal_LOWER_intercept = 0.0; // (Fractals_UPPER1_x, Fractals_UPPER1_y)と(Fractals_UPPER2_x, Fractals_UPPER2_y)
                                            // を結ぶ直線を想定したときの傾き
   double allig = 0.0;
   mFractals_UPPER1_y = 0.0;  // 直近のフラクタル値(UPPER)
   mFractals_UPPER1_x = 0;    // 直近のフラクタル値(UPPER)のシフト値
   mFractals_UPPER1_time = 0; // 直近のフラクタル値(UPPER)のシフト値の開始時間
   
   mFractals_UPPER2_y = 0.0;  // 2つ目のフラクタル値(UPPER)
   mFractals_UPPER2_x = 0;    // 2つ目のフラクタル値(UPPER)のシフト値
   mFractals_UPPER2_time = 0; // 2つ目のフラクタル値(UPPER)のシフト値の開始時間

   mFractals_UPPER3_y = 0.0;  // 3つ目のフラクタル値(UPPER)
   mFractals_UPPER3_x = 0;    // 3つ目のフラクタル値(UPPER)のシフト値
   mFractals_UPPER3_time = 0; // 3つ目のフラクタル値(UPPER)のシフト値の開始時間


   mFractals_LOWER1_y = 0.0;  // 直近のフラクタル値(LOWER)
   mFractals_LOWER1_x = 0;    // 直近のフラクタル値(LOWER)のシフト値
   mFractals_LOWER1_time = 0; // 直近のフラクタル値(LOWER)のシフト値の開始時間
   
   mFractals_LOWER2_y = 0.0;  // 2つ目のフラクタル値(LOWER)
   mFractals_LOWER2_x = 0;    // 2つ目のフラクタル値(LOWER)のシフト値
   mFractals_LOWER2_time = 0; // 2つ目のフラクタル値(LOWER)のシフト値の開始時間

   mFractals_LOWER3_y = 0.0;  // 3つ目のフラクタル値(LOWER)
   mFractals_LOWER3_x = 0;    // 3つ目のフラクタル値(LOWER)のシフト値
   mFractals_LOWER3_time = 0; // 3つ目のフラクタル値(LOWER)のシフト値の開始時間
   
   int i=0;


   // 現時点のフラクタルを取得する。
   //
   //
/*   // 従来型
   datetime bufDT = 0;  // フラクタルの発生した時間をPERIOD_M1で計算する時のバッファ
printf( "[%d]FRAC 3番目の山、谷を取得するために、強制的に   TEST_CALC_SLOPE_BY3 = trueを実施中");
TEST_CALC_SLOPE_BY3 = true;
   // 直近のフラクタルの山を取得する。
   for(i = 1; i <= FRACTALSPAN*2;i++) {
      if(Fractals_UPPER1_y == 0.0) {
         Fractals_UPPER1_y     = NormalizeDouble(iFractals(global_Symbol, 0, MODE_UPPER, i), global_Digits);
         Fractals_UPPER1_x     = i;  // シフト番号
         Fractals_UPPER1_time  = iTime(global_Symbol, 0, i);
      }
      else if(Fractals_UPPER2_y == 0.0) {
         Fractals_UPPER2_y     = NormalizeDouble(iFractals(global_Symbol, 0, MODE_UPPER, i), global_Digits);
         Fractals_UPPER2_x     = i;  // シフト番号
         Fractals_UPPER2_time  = iTime(global_Symbol, 0, i);     
      }     
      else if(TEST_CALC_SLOPE_BY3 == true && Fractals_UPPER3_y == 0.0) {
         Fractals_UPPER3_y     = NormalizeDouble(iFractals(global_Symbol, 0, MODE_UPPER, i), global_Digits);
         Fractals_UPPER3_x     = i;  // シフト番号
         Fractals_UPPER3_time  = iTime(global_Symbol, 0, i);        
      }      
       
      else {
         break;
      }
   }	

   // 【従来型】直近のフラクタルの谷を2つ取得する。
   for(i = 1; i <= FRACTALSPAN*2;i++) {
      if(Fractals_LOWER1_y == 0.0) {
         Fractals_LOWER1_y     = NormalizeDouble(iFractals(global_Symbol, 0, MODE_LOWER, i), global_Digits);
         Fractals_LOWER1_x     = i;  // シフト番号
         Fractals_LOWER1_time  = iTime(global_Symbol, 0, i);     
      }
      else if(Fractals_LOWER2_y == 0.0) {
         Fractals_LOWER2_y     = NormalizeDouble(iFractals(global_Symbol, 0, MODE_LOWER, i), global_Digits);
         Fractals_LOWER2_x     = i;  // シフト番号
         Fractals_LOWER2_time  = iTime(global_Symbol, 0, i);     
      }
      else if(TEST_CALC_SLOPE_BY3 == true && Fractals_LOWER3_y == 0.0) {
         Fractals_LOWER3_y     = NormalizeDouble(iFractals(global_Symbol, 0, MODE_LOWER, i), global_Digits);
         Fractals_LOWER3_x     = i;  // シフト番号
         Fractals_LOWER3_time  = iTime(global_Symbol, 0, i);     
      }
      else {
         break;
      }
   }   //for(i = 1; i <= FRACTALSPAN;i++) {
printf( "[%d]FRAC 【従来型】FRACTAL計算結果" , __LINE__);
         printf( "[%d]FRAC 【・従来型】Fractals_UPPER1 基準時刻Time[0]=%s シフト%dの時間%s フラクタル値=%s" , __LINE__,
            TimeToStr(Time[0]),
            Fractals_UPPER1_x,
            TimeToStr(Fractals_UPPER1_time),
            DoubleToStr(Fractals_UPPER1_y, global_Digits)
         );
         printf( "[%d]FRAC 【・従来型】Fractals_UPPER2 基準時刻Time[0]=%s シフト%dの時間%s フラクタル値=%s" , __LINE__,
            TimeToStr(Time[0]),
            Fractals_UPPER2_x,
            TimeToStr(Fractals_UPPER2_time),
            DoubleToStr(Fractals_UPPER2_y, global_Digits)
         );    
         printf( "[%d]FRAC 【・従来型】Fractals_UPPER3 基準時刻Time[0]=%s シフト%dの時間%s フラクタル値=%s" , __LINE__,
            Fractals_UPPER3_x,
            TimeToStr(Fractals_UPPER3_time),
            DoubleToStr(Fractals_UPPER3_y, global_Digits)
         ); 
         printf( "[%d]FRAC 【・従来型】Fractals_LOWER1 基準時刻Time[0]=%s シフト%dの時間%s フラクタル値=%s" , __LINE__,
            TimeToStr(Time[0]),
            Fractals_LOWER1_x,
            TimeToStr(Fractals_LOWER1_time),
            DoubleToStr(Fractals_LOWER1_y, global_Digits)
         );
         
         printf( "[%d]FRAC 【・従来型】Fractals_LOWER2 基準時刻Time[0]=%s シフト%dの時間%s フラクタル値=%s" , __LINE__,
            TimeToStr(Time[0]),
            Fractals_LOWER2_x,
            TimeToStr(Fractals_LOWER2_time),
            DoubleToStr(Fractals_LOWER2_y, global_Digits)
         );
         
         printf( "[%d]FRAC 【・従来型】Fractals_LOWER3 基準時刻Time[0]=%s シフト%dの時間%s フラクタル値=%s" , __LINE__,
            TimeToStr(Time[0]),
            Fractals_LOWER3_x,
            TimeToStr(Fractals_LOWER3_time),
            DoubleToStr(Fractals_LOWER3_y, global_Digits)
         );
*/
// ***********************************************************************
// 次の構造体型が正しく動いていることを確認するため、変数を初期化する。
// ***********************************************************************
/*
   Fractals_UPPER1_y = 0.0;  // 直近のフラクタル値(UPPER)
   Fractals_UPPER1_x = 0;    // 直近のフラクタル値(UPPER)のシフト値
   Fractals_UPPER1_time = 0; // 直近のフラクタル値(UPPER)のシフト値の開始時間
   
   Fractals_UPPER2_y = 0.0;  // 2つ目のフラクタル値(UPPER)
   Fractals_UPPER2_x = 0;    // 2つ目のフラクタル値(UPPER)のシフト値
   Fractals_UPPER2_time = 0; // 2つ目のフラクタル値(UPPER)のシフト値の開始時間

   Fractals_UPPER3_y = 0.0;  // 3つ目のフラクタル値(UPPER)
   Fractals_UPPER3_x = 0;    // 3つ目のフラクタル値(UPPER)のシフト値
   Fractals_UPPER3_time = 0; // 3つ目のフラクタル値(UPPER)のシフト値の開始時間


   Fractals_LOWER1_y = 0.0;  // 直近のフラクタル値(LOWER)
   Fractals_LOWER1_x = 0;    // 直近のフラクタル値(LOWER)のシフト値
   Fractals_LOWER1_time = 0; // 直近のフラクタル値(LOWER)のシフト値の開始時間
   
   Fractals_LOWER2_y = 0.0;  // 2つ目のフラクタル値(LOWER)
   Fractals_LOWER2_x = 0;    // 2つ目のフラクタル値(LOWER)のシフト値
   Fractals_LOWER2_time = 0; // 2つ目のフラクタル値(LOWER)のシフト値の開始時間

   Fractals_LOWER3_y = 0.0;  // 3つ目のフラクタル値(LOWER)
   Fractals_LOWER3_x = 0;    // 3つ目のフラクタル値(LOWER)のシフト値
   Fractals_LOWER3_time = 0; // 3つ目のフラクタル値(LOWER)のシフト値の開始時間
   */
// ***********************************************************************
            
   //
   //
   // 引数m_st_Fractalsが空ならば、フラクタルを取得する。   
   if(m_st_Fractals[0].calcTime <= 0) {
printf( "[%d]FRACテスト" , __LINE__);
   
      get_Fractals(m_st_Fractals);
   }
   read_FracST_TO_Param(m_st_Fractals,
                        mFractals_UPPER1_y,      //直近のフラクタル値(UPPER)
                        mFractals_UPPER1_x,      //直近のフラクタル値(UPPER)のシフト値
                        mFractals_UPPER1_time, // フラクタルを取得したシフト値のTime

                        mFractals_UPPER2_y,      //2つ目のフラクタル値(UPPER)
                        mFractals_UPPER2_x,      //2つ目のフラクタル値(UPPER)のシフト値
                        mFractals_UPPER2_time, // フラクタルを取得したシフト値のTime

                        mFractals_UPPER3_y,      //2つ目のフラクタル値(UPPER)
                        mFractals_UPPER3_x,      //2つ目のフラクタル値(UPPER)のシフト値
                        mFractals_UPPER3_time, // フラクタルを取得したシフト値のTime

                        mFractals_LOWER1_y,      //直近のフラクタル値(LOWER)
                        mFractals_LOWER1_x,      //直近のフラクタル値(LOWER)のシフト値
                        mFractals_LOWER1_time, // フラクタルを取得したシフト値のTime

                        mFractals_LOWER2_y,      //2つ目のフラクタル値(LOWER)
                        mFractals_LOWER2_x,      //2つ目のフラクタル値(LOWER)のシフト値
                        mFractals_LOWER2_time, // フラクタルを取得したシフト値のTime   

                        mFractals_LOWER3_y,      //2つ目のフラクタル値(LOWER)
                        mFractals_LOWER3_x,      //2つ目のフラクタル値(LOWER)のシフト値
                        mFractals_LOWER3_time  // フラクタルを取得したシフト値のTime  
   );

/*printf( "[%d]FRAC 【構造体型】Fractals_UPPER1 基準時刻Time[0]=%s シフト%dの時間%s フラクタル値=%s" , __LINE__,
   TimeToStr(Time[0]),
   Fractals_UPPER1_x,
   TimeToStr(Fractals_UPPER1_time),
   DoubleToStr(Fractals_UPPER1_y, global_Digits)
);         
printf( "[%d]FRAC 【構造体型】Fractals_UPPER2 基準時刻Time[0]=%s シフト%dの時間%s フラクタル値=%s" , __LINE__,
   TimeToStr(Time[0]),
   Fractals_UPPER2_x,
   TimeToStr(Fractals_UPPER2_time),
   DoubleToStr(Fractals_UPPER2_y, global_Digits)
);         
printf( "[%d]FRAC 【構造体型】Fractals_UPPER3 基準時刻Time[0]=%s シフト%dの時間%s フラクタル値=%s" , __LINE__,
   TimeToStr(Time[0]),
   Fractals_UPPER3_x,
   TimeToStr(Fractals_UPPER1_time),
   DoubleToStr(Fractals_UPPER3_y, global_Digits)
);         
printf( "[%d]FRAC 【構造体型】Fractals_LOWER1 基準時刻Time[0]=%s シフト%dの時間%s フラクタル値=%s" , __LINE__,
   TimeToStr(Time[0]),
   Fractals_LOWER1_x,
   TimeToStr(Fractals_LOWER1_time),
   DoubleToStr(Fractals_LOWER1_y, global_Digits)
);         
printf( "[%d]FRAC 【構造体型】Fractals_LOWER2 基準時刻Time[0]=%s シフト%dの時間%s フラクタル値=%s" , __LINE__,
   TimeToStr(Time[0]),
   Fractals_LOWER2_x,
   TimeToStr(Fractals_LOWER1_time),
   DoubleToStr(Fractals_LOWER2_y, global_Digits)
);         
printf( "[%d]FRAC 【構造体型】Fractals_LOWER3 基準時刻Time[0]=%s シフト%dの時間%s フラクタル値=%s" , __LINE__,
   TimeToStr(Time[0]),
   Fractals_LOWER3_x,
   TimeToStr(Fractals_LOWER3_time),
   DoubleToStr(Fractals_LOWER3_y, global_Digits)
);   */
  


   // *******************************************************//
/*printf( "[%d]FRAC 直近が山か谷かを判断　山１=%d=%s  谷1=%d=%s" , __LINE__,
      Fractals_UPPER1_time, 
      TimeToStr(Fractals_UPPER1_time),
      Fractals_LOWER1_time, 
      TimeToStr(Fractals_LOWER1_time)      
      );*/

   int fracLastMountORBottom = FRAC_NONE; // 直近がフラクタルの山FRAC_MOUNTか谷FRAC_BOTTOMか。
   double lastMount = 0.0;
   double lastBottom = 0.0;
   
   if(mFractals_UPPER1_time > mFractals_LOWER1_time //山の方が、将来
        && mFractals_LOWER1_time > 0) { 
      fracLastMountORBottom = FRAC_MOUNT;
      lastMount  = mFractals_UPPER1_y;
      lastBottom = DOUBLE_VALUE_MIN;
//printf( "[%d]FRAC 直近が山のため、発生するとしたら、ショート" , __LINE__);
      
   }
   else if(mFractals_UPPER1_time < mFractals_LOWER1_time  //谷の方が将来
       && mFractals_UPPER1_time > 0) {
      fracLastMountORBottom = FRAC_BOTTOM;
      lastMount  = DOUBLE_VALUE_MIN;
      lastBottom = mFractals_LOWER1_y;
//printf( "[%d]FRAC 直近が谷のため、発生するとしたら、ロング" , __LINE__);
   }
   else {
      fracLastMountORBottom = FRAC_NONE;
      return NO_SIGNAL;
   }  

   // 計算したフラクタル値を出力用引数にセットする。
   /*
   mFractals_UPPER1_y    = Fractals_UPPER1_y;
   mFractals_UPPER1_x    = Fractals_UPPER1_x;
   mFractals_UPPER1_time = Fractals_UPPER1_time;
   mFractals_UPPER2_y    = Fractals_UPPER2_y;
   mFractals_UPPER2_x    = Fractals_UPPER2_x;
   mFractals_UPPER2_time = Fractals_UPPER2_time;
   mFractals_LOWER1_y    = Fractals_LOWER1_y;
   mFractals_LOWER1_x    = Fractals_LOWER1_x;
   mFractals_LOWER1_time = Fractals_LOWER1_time;
   mFractals_LOWER2_y    = Fractals_LOWER2_y;
   mFractals_LOWER2_x    = Fractals_LOWER2_x;
   mFractals_LOWER2_time = Fractals_LOWER2_time;
   */

/*
printf( "[%d]FRAC UPPER1_y=%s x=%d t=%s" , __LINE__,
   DoubleToStr(mFractals_UPPER1_y, global_Digits),
   mFractals_UPPER1_x,
   TimeToStr(mFractals_UPPER1_time));
printf( "[%d]FRAC UPPER2_y=%s x=%d t=%s" , __LINE__,
   DoubleToStr(mFractals_UPPER2_y, global_Digits),
   mFractals_UPPER2_x,
   TimeToStr(mFractals_UPPER2_time));
     
printf( "[%d]FRAC LOWER1_y=%s x=%d t=%s" , __LINE__,
   DoubleToStr(mFractals_LOWER1_y, global_Digits),
   mFractals_LOWER1_x,
   TimeToStr(mFractals_LOWER1_time));
printf( "[%d]FRAC LOWER2_y=%s x=%d t=%s" , __LINE__,
   DoubleToStr(mFractals_LOWER2_y, global_Digits),
   mFractals_LOWER2_x,
   TimeToStr(mFractals_LOWER2_time));
  */ 

   // フラクタルの山と谷を各2つ取得できなければ、売買フラグ無し。
   if( (mFractals_UPPER1_y == 0.0) ||  (mFractals_UPPER2_y == 0.0)  
       || (mFractals_LOWER1_y == 0.0) || (mFractals_LOWER2_y == 0.0) ) {
printf( "[%d]FRACテスト" , __LINE__);
       
      return NO_SIGNAL;
   }


   //
   // 山、谷をそれぞれ2つまたは3つ使って回帰分析する。
   // 
   int wide_Digits = global_Digits * 2;
    
   //
   // 谷を結ぶ直線の傾きと切片を計算する。
   //
   double buf_y[10];  // 重回帰分析用のバッファ。y軸であるフラクタルの値が入る
   double buf_x[10];  // 重回帰分析用のバッファ。x軸であるシフト番号が入る。
   int    buf_dataNum;// 重回帰分析用のバッファ。データ数が入る。

   // 山を結ぶ直線の傾きと切片を計算する。
   ArrayInitialize(buf_y, 0.0);
   ArrayInitialize(buf_x, 0.0);
   buf_dataNum = 0;

   buf_y[0] = NormalizeDouble(mFractals_UPPER2_y, wide_Digits);
   buf_y[1] = NormalizeDouble(mFractals_UPPER1_y, wide_Digits);
   buf_x[0] = (double) mFractals_UPPER2_x;
   buf_x[1] = (double) mFractals_UPPER1_x;
   buf_dataNum = 2;
   fracSignal_UPPER_slope = 0.0;  // 山を結ぶ直線の傾き
   fracSignal_UPPER_intercept = 0.0;  // 山を結ぶ直線の切片
   bool flagLineM = calcRegressionLine(buf_y, buf_x, buf_dataNum, fracSignal_UPPER_slope, fracSignal_UPPER_intercept); // 重回帰分析版
   if(flagLineM == true) {
      // x軸がシフト番号のため、傾きが正負逆になっている。そのため、修正する。
      fracSignal_UPPER_slope = fracSignal_UPPER_slope * (-1);
/*      printf( "[%d]FRAC　重回帰　山の傾きと切片の計算　傾き   =%s  切片  =%s" , __LINE__, 
              DoubleToStr(fracSignal_UPPER_slope, global_Digits*2), 
              DoubleToStr(fracSignal_UPPER_intercept, global_Digits*2)); */
   }
   else {
         printf( "[%d]FRAC　重回帰　山の傾きと切片の計算失敗  (x=%s, y=%s)  (x=%s, y=%s)" , __LINE__, 
            DoubleToStr(buf_x[1], global_Digits), DoubleToStr(buf_y[1], wide_Digits),
            DoubleToStr(buf_x[0], global_Digits), DoubleToStr(buf_y[0], wide_Digits));

      return NO_SIGNAL;
   }
   
   
   // 山、谷をそれぞれ、3つ使う場合
   if(TEST_CALC_SLOPE_BY3 == true) {
      // 3つの山を結ぶ直線の傾きと切片を計算する。
      ArrayInitialize(buf_y, 0.0);
      ArrayInitialize(buf_x, 0.0);
      buf_dataNum = 0;

      buf_y[0] = NormalizeDouble(mFractals_UPPER3_y, wide_Digits);
      buf_y[1] = NormalizeDouble(mFractals_UPPER2_y, wide_Digits);
      buf_y[2] = NormalizeDouble(mFractals_UPPER1_y, wide_Digits);
      buf_x[0] = (double) mFractals_UPPER3_x;
      buf_x[1] = (double) mFractals_UPPER2_x;
      buf_x[2] = (double) mFractals_UPPER1_x;
      buf_dataNum = 3;
      fracSignal_UPPER_slope = 0.0;  // 山を結ぶ直線の傾き
      fracSignal_UPPER_intercept = 0.0;  // 山を結ぶ直線の切片
      flagLineM = calcRegressionLine(buf_y, buf_x, buf_dataNum, fracSignal_UPPER_slope, fracSignal_UPPER_intercept); // 重回帰分析版
      if(flagLineM == true) {
         // x軸がシフト番号のため、傾きが正負逆になっている。そのため、修正する。
         fracSignal_UPPER_slope = fracSignal_UPPER_slope * (-1);
/*         printf( "[%d]FRAC　重回帰3データ　谷の傾きと切片の計算　傾き   =%s  切片  =%s" , __LINE__, 
                 DoubleToStr(fracSignal_UPPER_slope, global_Digits*2), 
                 DoubleToStr(fracSignal_UPPER_intercept, global_Digits*2)); */
      }
      else {
         printf( "[%d]FRAC　重回帰3データ　山の傾きと切片の計算失敗  (x=%s, y=%s)  (x=%s, y=%s)  (x=%s, y=%s)" , __LINE__, 
            DoubleToStr(buf_x[2], global_Digits), DoubleToStr(buf_y[2], wide_Digits),
            DoubleToStr(buf_x[1], global_Digits), DoubleToStr(buf_y[1], wide_Digits),
            DoubleToStr(buf_x[0], global_Digits), DoubleToStr(buf_y[0], wide_Digits)
         ); 
         
         return NO_SIGNAL;
      }       
   }

   //
   // よって、
   // 山を結ぶ直線から推定するシフト2の時の直線上(=フラクタル)の値は、X = 2を代入して
   fracSignal_UPPER_Shift2 = NormalizeDouble(fracSignal_UPPER_slope, wide_Digits) * 2.0 + NormalizeDouble(fracSignal_UPPER_intercept, wide_Digits); 

   // 山を結ぶ直線から推定するシフト1の時の直線上(=フラクタル)の値は、X = 1を代入して
   fracSignal_UPPER_Shift1  = NormalizeDouble(fracSignal_UPPER_slope, wide_Digits) * 1.0 + NormalizeDouble(fracSignal_UPPER_intercept, wide_Digits); 

   //
   // 谷を結ぶ直線の傾きと切片を計算する。
   //
   ArrayInitialize(buf_y, 0.0);
   ArrayInitialize(buf_x, 0.0);
   buf_dataNum = 0;

   buf_y[0] = NormalizeDouble(mFractals_LOWER2_y, wide_Digits);
   buf_y[1] = NormalizeDouble(mFractals_LOWER1_y, wide_Digits);
   buf_x[0] = (double) mFractals_LOWER2_x;
   buf_x[1] = (double) mFractals_LOWER1_x;
   buf_dataNum = 2;
   fracSignal_LOWER_slope = 0.0;     // 谷を結ぶ直線の傾き
   fracSignal_LOWER_intercept = 0.0; // 谷を結ぶ直線の切片

   bool flagLineB = calcRegressionLine(buf_y, buf_x, buf_dataNum, fracSignal_LOWER_slope, fracSignal_LOWER_intercept); // 重回帰分析版
   if(flagLineB == true) {
      // x軸がシフト番号のため、傾きが正負逆になっている。そのため、修正する。
      fracSignal_LOWER_slope = fracSignal_LOWER_slope * (-1);

   }
   else {
/*         printf( "[%d]FRAC　重回帰　谷の傾きと切片の計算失敗  (x=%s, y=%s)  (x=%s, y=%s)" , __LINE__, 
            DoubleToStr(buf_x[1], global_Digits), DoubleToStr(buf_y[1], wide_Digits),
            DoubleToStr(buf_x[0], global_Digits), DoubleToStr(buf_y[0], wide_Digits)
         ); */
      return NO_SIGNAL;
   }      
   
   
   // 実験用。山を3つ使って回帰分析する。実験につき、余計な計算が入ることは無視する。
   if(TEST_CALC_SLOPE_BY3 == true) {
      // 3つの山を結ぶ直線の傾きと切片を計算する。
      ArrayInitialize(buf_y, 0.0);
      ArrayInitialize(buf_x, 0.0);
      buf_dataNum = 0;

      buf_y[0] = NormalizeDouble(mFractals_LOWER3_y, wide_Digits);
      buf_y[1] = NormalizeDouble(mFractals_LOWER2_y, wide_Digits);
      buf_y[2] = NormalizeDouble(mFractals_LOWER1_y, wide_Digits);
      buf_x[0] = (double) mFractals_LOWER3_x;
      buf_x[1] = (double) mFractals_LOWER2_x;
      buf_x[2] = (double) mFractals_LOWER1_x;
      buf_dataNum = 3;
      fracSignal_LOWER_slope = 0.0;  // 山を結ぶ直線の傾き
      fracSignal_LOWER_intercept = 0.0;  // 山を結ぶ直線の切片
      flagLineB = calcRegressionLine(buf_y, buf_x, buf_dataNum, fracSignal_LOWER_slope, fracSignal_LOWER_intercept); // 重回帰分析版
      if(flagLineB == true) {
         // x軸がシフト番号のため、傾きが正負逆になっている。そのため、修正する。
         fracSignal_LOWER_slope = fracSignal_LOWER_slope * (-1);
         /*printf( "[%d]FRAC　重回帰3データ　谷の傾きと切片の計算　傾き   =%s  切片  =%s" , __LINE__, 
                 DoubleToStr(fracSignal_LOWER_slope, global_Digits*2), 
                 DoubleToStr(fracSignal_LOWER_intercept, global_Digits*2)); */
      }
      else {
/*         printf( "[%d]FRAC　重回帰　山の傾きと切片の計算失敗  (x=%s, y=%s)  (x=%s, y=%s)  (x=%s, y=%s)" , __LINE__, 
            DoubleToStr(buf_x[2], global_Digits), DoubleToStr(buf_y[2], wide_Digits),
            DoubleToStr(buf_x[1], global_Digits), DoubleToStr(buf_y[1], wide_Digits),
            DoubleToStr(buf_x[0], global_Digits), DoubleToStr(buf_y[0], wide_Digits));*/
         return NO_SIGNAL;
      }      
   }



   //
   // よって、
   // 谷を結ぶ直線から推定するシフト2の時の直線上(=フラクタル)の値は、X = 2を代入して
   fracSignal_LOWER_Shift2 = NormalizeDouble(fracSignal_LOWER_slope, global_Digits) * 2.0 + NormalizeDouble(fracSignal_LOWER_intercept, global_Digits); 

   // 山を結ぶ直線から推定するシフト1の時の直線上(=フラクタル)の値は、X = 1を代入して
   fracSignal_LOWER_Shift1  = NormalizeDouble(fracSignal_LOWER_slope, global_Digits) * 1.0 + NormalizeDouble(fracSignal_LOWER_intercept, global_Digits); 

   double iClose1 = iClose(global_Symbol, 0, 1);
   double iClose2 = iClose(global_Symbol, 0, 2);
   if(iClose1 <= 0.0 || iClose2 <= 0.0) {
      //　シフト１，２の終値を取得できなかったので、何もしない。
      ret = NO_SIGNAL;
//printf( "[%d]FRACテスト　フラグ=%d  ただし、BUY=%d SELL=%d" , __LINE__, ret, BUY_SIGNAL, SELL_SIGNAL);
      
   }

   double alli_TEETH = 0.0;
   // ロングのシグナル設定
   // ①直前が谷。これを、買いフラクタル（下向き）とする。
   // ②Close1, Close2が直前の山を結ぶ線をうわ抜けて、トレンドを上にブレイクした時。
   // ③直前の谷である買いフラクタル（下向き）が、アリゲータの歯より上であること。
   if(fracLastMountORBottom == FRAC_BOTTOM) {      // ←①
                                                  // ↓②
      if( (NormalizeDouble(fracSignal_UPPER_Shift2, wide_Digits) <= NormalizeDouble(iClose2, wide_Digits) && NormalizeDouble(fracSignal_UPPER_Shift1, wide_Digits) <= NormalizeDouble(iClose1, wide_Digits)) // Close[1], Close[2]が両方ともうわ抜け
           ||
          (NormalizeDouble(fracSignal_UPPER_Shift2, wide_Digits) >= NormalizeDouble(iClose2, wide_Digits) && NormalizeDouble(fracSignal_UPPER_Shift1, wide_Digits) <= NormalizeDouble(iClose1, wide_Digits))  // Close[2]は直線を下回ったが、Close[1]がうわ抜け        
      ){
         alli_TEETH = iAlligator(global_Symbol,0,39,8,5,5,2,3,MODE_SMMA,PRICE_MEDIAN,MODE_GATORTEETH,1);
/*printf("[%d]FRAC　直近が谷　→　最後のロング判定　アリゲーターの歯=%s < 谷1=%sならショート確定。" , __LINE__, 
         DoubleToStr(alli_TEETH, wide_Digits),
         DoubleToStr(lastBottom, wide_Digits) );*/
         
         if(NormalizeDouble(lastBottom, wide_Digits) >= NormalizeDouble(alli_TEETH, wide_Digits)) {  //←③
            ret = BUY_SIGNAL;
         }
         else {
/*printf("[%d]FRAC　直近が谷　→　ロング不可　アリゲーターの歯=%s < 谷1=%sを満たせず。" , __LINE__, 
         DoubleToStr(alli_TEETH, wide_Digits),
         DoubleToStr(lastBottom, wide_Digits) );*/
         }
      }
      else {
/*printf( "[%d]FRAC　直近が谷　→　ロング不可　山の回帰直線(1)=%s < Close1=%sを満たせず。参考：Frac2=%s  Close2=%s " , __LINE__, 
          DoubleToStr(fracSignal_UPPER_Shift1, wide_Digits),
          DoubleToStr(iClose1, wide_Digits),          
          DoubleToStr(fracSignal_UPPER_Shift2, wide_Digits),
          DoubleToStr(iClose2, wide_Digits)); */
      }
   }

   alli_TEETH = 0.0;
   // ショートのシグナル設定
   // ①直前が山。これを、売りフラクタル（上向き）とする。
   // ②Close1, Close2が直前の谷を結ぶ線を下抜けて、トレンドを下にブレイクした時。
   // ③直前の山である売りフラクタル（上向き）が、アリゲータの歯より下であること。
   if(fracLastMountORBottom == FRAC_MOUNT) {      // ←①
                                                  // ↓②
      if( (NormalizeDouble(fracSignal_LOWER_Shift2, wide_Digits) >= NormalizeDouble(iClose2, wide_Digits) && NormalizeDouble(fracSignal_LOWER_Shift1, wide_Digits) >= NormalizeDouble(iClose1, wide_Digits)) // Close[1], Close[2]が両方とも下抜け
           ||
          (NormalizeDouble(fracSignal_LOWER_Shift2, wide_Digits) <= NormalizeDouble(iClose2, wide_Digits) && NormalizeDouble(fracSignal_LOWER_Shift1, wide_Digits) >= NormalizeDouble(iClose1, wide_Digits))  // Close[2]は直線を上回ったが、Close[1]が下抜け
      ){
         alli_TEETH = iAlligator(global_Symbol,0,39,8,5,5,2,3,MODE_SMMA,PRICE_MEDIAN,MODE_GATORTEETH,1);
/*printf("[%d]FRAC 直近が山　→　最後のショート判定　アリゲーターの歯=%s > 山1=%sならショート確定。" , __LINE__, 
         DoubleToStr(alli_TEETH, wide_Digits),
         DoubleToStr(lastMount, wide_Digits) );*/
         
         if(NormalizeDouble(lastMount, wide_Digits) <= NormalizeDouble(alli_TEETH, wide_Digits)) {  //←③
            ret = SELL_SIGNAL;
         }
         else {
/*printf("[%d]FRAC 直近が山　→　ショート不可　アリゲーターの歯=%s > 山1=%sを満たせず。" , __LINE__, 
         DoubleToStr(alli_TEETH, wide_Digits),
         DoubleToStr(lastMount, wide_Digits) );*/
         }
      }
      else {
/*printf( "[%d]FRAC 直近が山　→　ショート不可　谷の回帰直線(1)=%s > Close1=%sを満たせず。参考：Frac2=%s  Close2=%s " , __LINE__, 
          DoubleToStr(fracSignal_LOWER_Shift1, wide_Digits),
          DoubleToStr(iClose1, wide_Digits),          
          DoubleToStr(fracSignal_LOWER_Shift2, wide_Digits),
          DoubleToStr(iClose2, wide_Digits) ); */
      }
   }

   //
   //
   // アリゲーターによるスクリーニング追加。
   // ②アリゲータによる上昇傾向と下降傾向
   if(FRACTALMETHOD >= 2) {
//printf( "[%d]FRACテスト　フラグ=%d  ただし、BUY=%d SELL=%d" , __LINE__, ret, BUY_SIGNAL, SELL_SIGNAL);
   
      if(ret == BUY_SIGNAL || ret == SELL_SIGNAL) {
         int trendAlligator = get_Trend_Alligator(global_Symbol, 
                                                  global_Period,
                                                  1);
         if(ret == BUY_SIGNAL) {
            // 上昇トレンドの時に、シグナルを維持
            if(trendAlligator == UpTrend) {
               // retは、変更なし
            }
            else {
//printf("[%d]FRAC BUY_SIGNALだが、get_Trend_Alligatorのトレンドが>%d<。UpTrend=1 Down=-1 NoTrend=0" , __LINE__, trendAlligator);
            
               ret = NO_SIGNAL;
            }
         }
         else if(ret == SELL_SIGNAL) {
            // 下降トレンドの時に、シグナルを維持
            if(trendAlligator == DownTrend) {
               // retは、変更なし
            }
            else {
//printf("[%d]FRAC SELL_SIGNALだが、get_Trend_Alligatorのトレンドが>%d<。UpTrend=1 Down=-1 NoTrend=0" , __LINE__, trendAlligator);
            
               ret = NO_SIGNAL;
            }
         }
      } // if(ret == BUY_SIGNAL || ret == SELL_SIGNAL) 
   }    // if(FRACTALMETHOD >= 2)
//printf( "[%d]FRACテスト" , __LINE__);

   //
   //
   // FRAC以外にゴールデンクロス、デッドクロスを売買シグナル判断に追加した。
   // ・ゴールデンクロスの方が、デッドクロスよりも近ければ、買いシグナルを維持。
   //　・デッドクロスの方が、ゴールデンクロスよりも近ければ、売りシグナルを維持。
   // ・ゴールデンクロス、デッドクロスを計算できなければ、現状維持。（＝Zigzagを優先）
   //
   int lastGC = 0; //直近のゴールデンクロスが発生したシフト
   int lastDC = 0; //直近のデッドクロスが発生したシフト
   if(FRACTALMETHOD >= 3) {
   
      bool flag_GCDC = getLastMA_Cross(Period(), // 入力：移動平均を計算するための時間軸
                                       1, // 入力：計算開始位置
                                       lastGC,    // 出力：直近のゴールデンクロスが発生したシフト
                                       lastDC);
      if(flag_GCDC == false) {
         // 何もしない。FRACの結果に従う。
      }
      else {
         // retがFRACでBUY_SIGNALの時
         if(ret == BUY_SIGNAL) {
            //GCの方が近ければ、sig_entryはそのまま（BUY_SIGNAL）。それ以外はNO_SIGNAL
            if(lastGC >= 0 && lastGC < lastDC) {
               // retは、変更なし
            }
            else {
               // デッドクロスの方が近いので、BUY＿SIGNALは取りやめ
               ret = NO_SIGNAL;
            }
         }
         else if(ret == SELL_SIGNAL) {
            //DCの方が近ければ、retはそのまま（SELL_SIGNAL）。それ以外はNO_SIGNAL
            if(lastDC >= 0 && lastGC > lastDC) {
               // retは、変更なし
            }
            else {
               // ゴールデンクロスの方が近いので、BUY＿SIGNALは取りやめ
               ret = NO_SIGNAL;
            }
         }
      }
   }       // if(FRACTALMETHOD >= 3)

   //
   //
   // FRAC以外に1つ長い足で、シフト1，2，3のMAの傾きを売買シグナル判断に追加した。
   // ・傾きが、正ならば、買いシグナルを維持。
   // ・傾きが、負ならば、売りシグナルを維持。
   // ・傾きを計算できなければ、現状維持。（＝Zigzagを優先）
   if(FRACTALMETHOD >= 4) {
   
      int currTF   = -1; //　現在の時間軸
      int longerTF = -1; // １つ上の時間軸   
      currTF = getTimeFrameReverse(global_Period); //引数にPERIOD_M1を渡せば1, PERIOD_M５を渡せば2を返す。返す範囲は、1～9まで。

      if(currTF >= 9) {  // より上位の時間軸が存在しないため、最大の時間軸PERIOD_MN1とする。
         longerTF = PERIOD_MN1;
      }
      else {                  // 一般的にこの範囲に入り、PERIOD_M1(=1)～PERIOD_W1(=8)である。１を加えて、ENUM_TIMEFRAMESに変換する。
         longerTF = getTimeFrame(currTF + 1);
      }
      // 上記の処理をしても、currTFが0か負は、通常、ありえないため、PERIOD_H1を1つ上の時間軸とする。
      // FRACを優先を優先するため、この計算ができなくとも、処理を進める。
      if(currTF <= 0) {       
         longerTF = PERIOD_H1;
      }
      double data[4];  // data[0]=シフト1のMA値、data[1]=シフト2のMA値、data[2]=シフト3のMA値
      int    dataNum = 3;
      ArrayInitialize(data, 0.0);
      double slope_longerLEG     = DOUBLE_VALUE_MIN;
      double intercept_longerLEG = DOUBLE_VALUE_MIN;
   
      data[0] = iMA(global_Symbol,// 通貨ペア
                    longerTF,     // 時間軸
                    5,            // MAの平均期間
                    0,            // MAシフト
                    MODE_SMMA,     // MAの平均化メソッド
                    PRICE_CLOSE,  // 適用価格
                    1             // シフト
                    );   
      data[1] = iMA(global_Symbol,// 通貨ペア
                    longerTF,     // 時間軸
                    5,            // MAの平均期間
                    0,            // MAシフト
                    MODE_SMMA,     // MAの平均化メソッド
                    PRICE_CLOSE,  // 適用価格
                    2             // シフト
                    );   
      data[2] = iMA(global_Symbol,// 通貨ペア
                    longerTF,     // 時間軸
                    5,            // MAの平均期間
                    0,            // MAシフト
                    MODE_SMMA,     // MAの平均化メソッド
                    PRICE_CLOSE,  // 適用価格
                    3             // シフト
                    );   

      if(data[0] > 0.0 && data[1] > 0.0 && data[2] > 0.0) {
         // ※ data[0]がx=0、data[1]がx=1というように、data[]にはグラフの左（xが小さい方）から右（xが大きい方）のデータが入っている前提。
         // ※ そのため、シフトのようにxの値が大きいほど過去を意味する場合は、計算後に傾きの正負を反転させる必要あり。
         bool flagResult = calcRegressionLine(data, dataNum, slope_longerLEG, intercept_longerLEG);         
         if(slope_longerLEG > DOUBLE_VALUE_MIN) {
            slope_longerLEG = slope_longerLEG * (-1);
         }
         if(ret == BUY_SIGNAL) {
            if(slope_longerLEG >= 0) {
               // sig_entryは、変更なし
            } 
            else {
               ret = NO_SIGNAL;
            }
         }
         else if(ret == SELL_SIGNAL) {
            if(slope_longerLEG <= 0) {
               // sig_entryは、変更なし
            } 
            else {
               ret = NO_SIGNAL;
            }
         }
      }
   }       // if(FRACTALMETHOD >= 4)

   //
   //
   // 直近のフラクタルを結んだ線の傾きでスクリーニング追加。
   // BUY_SIGNALは、 直近の山、谷を結んだ直線の傾きが共に0か正の時のみ維持。
   // SELL_SIGNALは、直近の山、谷を結んだ直線の傾きが共に0か負の時のみ維持。
   if(FRACTALMETHOD >= 5) {
      if(ret == BUY_SIGNAL || ret == SELL_SIGNAL) {
/*printf( "[%d]FRAC　FRACTALMETHOD >= 3の時、山、谷を結んだ直線の傾きで制限する。", __LINE__);
printf( "[%d]FRAC　山の傾きと切片の計算　傾き   =%s  切片  =%s" , __LINE__, DoubleToStr(fracSignal_UPPER_slope, global_Digits), DoubleToStr(fracSignal_UPPER_intercept, global_Digits)); 
printf( "[%d]FRAC　谷の傾きと切片の計算　傾き   =%s  切片  =%s" , __LINE__, DoubleToStr(fracSignal_LOWER_slope, global_Digits), DoubleToStr(fracSignal_LOWER_intercept, global_Digits)); */

         // 買いシグナルが維持できるかを確認 下値切り上げ
//         if(ret == BUY_SIGNAL && fracSignal_UPPER_slope >= 0.0 && fracSignal_LOWER_slope >= 0.0 ) {
         if(ret == BUY_SIGNAL && fracSignal_LOWER_slope >= 0.0 ) {
            // retは、変更なし
         }
         else {
/*printf("[%d]FRAC BUY_SIGNALだが、傾きがfracSignal_UPPER_slope>%s<  fracSignal_LOWER_slope" , __LINE__, 
            DoubleToStr(fracSignal_UPPER_slope, global_Digits*2 ), 
            DoubleToStr(fracSignal_LOWER_slope, global_Digits*2));*/
         
            ret = NO_SIGNAL;
         }

         // 売りシグナルが維持できるかを確認　上値切り下げ
         if(ret == SELL_SIGNAL && fracSignal_UPPER_slope <= 0.0 ) {
            // retは、変更なし
         }
         else {
/*printf("[%d]FRAC SELL_SIGNALだが、傾きがfracSignal_UPPER_slope>%s<  fracSignal_LOWER_slope" , __LINE__, 
            DoubleToStr(fracSignal_UPPER_slope, global_Digits*2),
            DoubleToStr(fracSignal_LOWER_slope, global_Digits*2));*/
            ret = NO_SIGNAL;
         }
      } // if(ret == BUY_SIGNAL || ret == SELL_SIGNAL) 
   }    // if(FRACTALMETHOD >= 5)

   return ret;
}



//------------------------------------------------------------------
//| Fracでも、Zigzagに似せた損切値更新ロジックを使う。
//| ・取引が持つ損切値より有利であれば更新する。。
//| ・2つ前の谷より直前の谷が高い場合のみ、ロングのストップを直前の谷に更新する。
//| ・2つ前の山より直前の山が低い場合のみ、ショートのストップを直前の山に更新する。
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
bool update_AllOrdersSLFrac(int mMagic,                 // 更新対象とする取引のマジックナンバー
                            string mSymbol,             // 更新対象とする取引の通貨ペア
                            string mStrategy,           // 更新対象とする取引の戦略名。コメント欄に該当する。
                            st_Fractal &m_st_Fractals[] // 更新時点のフラクタル値
) {
   double mFractals_UPPER1_y      = 0.0; // 直近のフラクタル値(UPPER)
   int    mFractals_UPPER1_x      = 0;   // 直近のフラクタル値(UPPER)のシフト値
   datetime mFractals_UPPER1_time = 0;   // フラクタルを取得したシフト値のTime

   double mFractals_UPPER2_y      = 0.0; // 2つ目のフラクタル値(UPPER)
   int    mFractals_UPPER2_x      = 0;   // 2つ目のフラクタル値(UPPER)のシフト値
   datetime mFractals_UPPER2_time = 0;   // フラクタルを取得したシフト値のTime

   double mFractals_UPPER3_y      = 0.0; // 2つ目のフラクタル値(UPPER)
   int    mFractals_UPPER3_x      = 0;   // 2つ目のフラクタル値(UPPER)のシフト値
   datetime mFractals_UPPER3_time = 0;   // フラクタルを取得したシフト値のTime

   double mFractals_LOWER1_y      = 0.0; // 直近のフラクタル値(LOWER)
   int    mFractals_LOWER1_x      = 0;   // 直近のフラクタル値(LOWER)のシフト値
   datetime mFractals_LOWER1_time = 0;   // フラクタルを取得したシフト値のTime

   double mFractals_LOWER2_y      = 0.0; // 2つ目のフラクタル値(LOWER)
   int    mFractals_LOWER2_x      = 0;   // 2つ目のフラクタル値(LOWER)のシフト値
   datetime mFractals_LOWER2_time = 0;   // フラクタルを取得したシフト値のTime   

   double mFractals_LOWER3_y      = 0.0; // 2つ目のフラクタル値(LOWER)
   int    mFractals_LOWER3_x      = 0;   // 2つ目のフラクタル値(LOWER)のシフト値
   datetime mFractals_LOWER3_time = 0;   // フラクタルを取得したシフト値のTime  

   int i = 0;
   bool ret = true;
   double long_SL_Cand = 0.0;  // ロングの損切値候補
   double short_SL_Cand = 0.0; // ショートの損切値候補
   int mFlag = -1;             // OederModifyの返り値

   // 直前Fractalに値が無い場合は、Fractalを再計算する。
   if(m_st_Fractals[0].calcTime <= 0) {  
      // フラクタルの値を取得し、構造体st_Fractalsに入れる。
      bool flag_getFrac = get_Fractals(m_st_Fractals);
      if(flag_getFrac == false) {
         return false;
      }
   }

   read_FracST_TO_Param(m_st_Fractals,
                        mFractals_UPPER1_y,      //直近のフラクタル値(UPPER)
                        mFractals_UPPER1_x,      //直近のフラクタル値(UPPER)のシフト値
                        mFractals_UPPER1_time,   // フラクタルを取得したシフト値のTime

                        mFractals_UPPER2_y,      //2つ目のフラクタル値(UPPER)
                        mFractals_UPPER2_x,      //2つ目のフラクタル値(UPPER)のシフト値
                        mFractals_UPPER2_time,   // フラクタルを取得したシフト値のTime

                        mFractals_UPPER3_y,      //2つ目のフラクタル値(UPPER)
                        mFractals_UPPER3_x,      //2つ目のフラクタル値(UPPER)のシフト値
                        mFractals_UPPER3_time,   // フラクタルを取得したシフト値のTime

                        mFractals_LOWER1_y,      //直近のフラクタル値(LOWER)
                        mFractals_LOWER1_x,      //直近のフラクタル値(LOWER)のシフト値
                        mFractals_LOWER1_time,   // フラクタルを取得したシフト値のTime

                        mFractals_LOWER2_y,      //2つ目のフラクタル値(LOWER)
                        mFractals_LOWER2_x,      //2つ目のフラクタル値(LOWER)のシフト値
                        mFractals_LOWER2_time,   // フラクタルを取得したシフト値のTime   

                        mFractals_LOWER3_y,      //2つ目のフラクタル値(LOWER)
                        mFractals_LOWER3_x,      //2つ目のフラクタル値(LOWER)のシフト値
                        mFractals_LOWER3_time  // フラクタルを取得したシフト値のTime 
   );
/*
printf( "[%d]FRAC UPPER1_y=%s x=%d t=%s" , __LINE__,
   DoubleToStr(Fractals_UPPER1_y, global_Digits),
   Fractals_UPPER1_x,
   TimeToStr(Fractals_UPPER1_time));
   
printf( "[%d]FRAC UPPER2_y=%s x=%d t=%s" , __LINE__,
   DoubleToStr(Fractals_UPPER2_y, global_Digits),
   Fractals_UPPER2_x,
   TimeToStr(Fractals_UPPER2_time));
     
printf( "[%d]FRAC LOWER1_y=%s x=%d t=%s" , __LINE__,
   DoubleToStr(Fractals_LOWER1_y, global_Digits),
   Fractals_LOWER1_x,
   TimeToStr(Fractals_LOWER1_time));

printf( "[%d]FRAC LOWER2_y=%s x=%d t=%s" , __LINE__,
   DoubleToStr(Fractals_LOWER2_y, global_Digits),
   Fractals_LOWER2_x,
   TimeToStr(Fractals_LOWER2_time));
*/
   
   int LastMountORBottom = FRAC_NONE; // 直近がフラクタルの山FRAC_MOUNTか谷FRAC_BOTTOMか。
   if(mFractals_UPPER1_time > mFractals_LOWER1_time && mFractals_LOWER1_time > 0) { //山の方が、将来
      LastMountORBottom = FRAC_MOUNT;
   }
   else if(mFractals_UPPER1_time < mFractals_LOWER1_time && mFractals_UPPER1_time > 0) { //山の方が、過去
      LastMountORBottom = FRAC_BOTTOM;
   }
   else {
      LastMountORBottom = FRAC_NONE;
/*       printf( "[%d]FRAC FRACの直前の山と谷を判断できない。　UPPER1=%s=%d--%s LOWER1=%s=%d-%s 【参考】UPPER2=%s=%d-%s LOWER2=%s=%d-%s" , __LINE__,
               TimeToStr(mFractals_UPPER1_time), mFractals_UPPER1_time, DoubleToStr(mFractals_UPPER1_y, global_Digits),
               TimeToStr(mFractals_LOWER1_time), mFractals_LOWER1_time, DoubleToStr(mFractals_LOWER1_y, global_Digits),
               TimeToStr(mFractals_UPPER2_time), mFractals_UPPER2_time, DoubleToStr(mFractals_UPPER2_y, global_Digits),
               TimeToStr(mFractals_LOWER2_time), mFractals_LOWER2_time, DoubleToStr(mFractals_LOWER2_y, global_Digits)
      );*/

      return false;
   }
   


   // 直近がFracの谷であれば、ロングの損切値候補を計算する。
   // 2つ前の谷より直前の谷が高い場合のみ、ロングのストップを直前の谷にする。 
   if( (LastMountORBottom == FRAC_BOTTOM) 
        && (NormalizeDouble(mFractals_LOWER1_y, global_Digits) > NormalizeDouble(mFractals_LOWER2_y, global_Digits) && mFractals_LOWER2_y > 0.0)) {
         long_SL_Cand = mFractals_LOWER1_y;
   }
   // 直近がFracの山であれば、ショートの損切値候補を計算する。
   // 2つ前の山より直前の山が低い場合のみ、ショートのストップを直前の山にする。
   else if( (LastMountORBottom == FRAC_MOUNT)
             && (NormalizeDouble(mFractals_UPPER1_y, global_Digits) < NormalizeDouble(mFractals_UPPER2_y, global_Digits) && mFractals_UPPER1_y > 0.0)) {
         short_SL_Cand = mFractals_UPPER1_y;
        
   }
   else {
      ret = false;
   }


   // 口座情報を取得する。
   double mMarketinfoMODE_ASK = MarketInfo(mSymbol,MODE_ASK);
   double mMarketinfoMODE_BID = MarketInfo(mSymbol,MODE_BID);
   double mMarketinfoMODE_POINT = global_Points;
   double mMarketinfoMODE_STOPLEVEL = global_StopLevel;



   for(i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
         if(OrderMagicNumber() == mMagic) {
            if(StringCompare(OrderSymbol(),mSymbol) == 0 
               && StringFind(OrderComment(), mStrategy, 0) >= 0) {
               int    mTicket          = OrderTicket();
               double mOpen            = OrderOpenPrice();
               double mOrderStopLoss   = OrderStopLoss();
               double mOrderTakeProfit = OrderTakeProfit();
               int mBuySell            = OrderType();
    
               // ロングの場合の損切更新
               if(mBuySell == OP_BUY) {
                  // 注目しているOrderが、エントリー直後(損切値が0.0)の時は、
                  // ・エントリー直後(損切値が0.0)に、直前の谷をストップとする。 
                  // ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、損切値を設定しない。 
                  if(mOrderStopLoss <= 0.0) {
                     // 冒頭で、2つ前の谷より直前の谷が高い場合のみ、ロングのストップを直前の谷を更新候補long_SL_Candにしていれば、その値を設定できるか調べる。
                     if(long_SL_Cand > 0.0 && NormalizeDouble(long_SL_Cand, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // long_SL_Candを使って損切値を更新できるので、そのまま。
                     }
                     else { 
                       // long_SL_Candが制約により設定できないため、制約を満たす直近の谷を探す。
                       // 見つからなければ、設定もれを防ぐため、制約を満たす値を設定する。
                       double buf_long_SL_Cand = NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble((1+mMarketinfoMODE_STOPLEVEL) * mMarketinfoMODE_POINT, global_Digits);
                       buf_long_SL_Cand = get_Next_Lower_FRAC(global_Symbol,     // 通貨ペア
                                                              global_Period,     // タイムフレーム 
                                                              mFractals_LOWER1_x, // このシフト＋１以上のシフトでFractalを計算する。
                                                              buf_long_SL_Cand   // この値より小さな値を探す
                                                              );
                       if(buf_long_SL_Cand > DOUBLE_VALUE_MIN) {
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
                           printf( "[%d]FRACエラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]FRACエラー mOrderStopLoss=%s  long_SL_Cand=%s " , __LINE__,DoubleToStr(long_SL_Cand), DoubleToStr(mOrderTakeProfit));
                           printf( "[%d]FRACエラー mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                        
                           ret = false;
                        }
                        else {
                        }
                     }
                  }  // if(mOrderStopLoss <= 0.0) {
                  
                  // mOrderStopLossが設定済みの場合、
                  // 冒頭で、2つ前の谷より直前の谷が高い場合のみ、ロングのストップを直前の谷を更新候補long_SL_Candにしていれば、
                  // mOrderStopLoss > 0.0 かつ long_SL_Cand > mOrderStopLoss ＝　より有利な損切値であること
                  else if( mOrderStopLoss > 0.0 
                          && long_SL_Cand > 0.0 
                          && NormalizeDouble(long_SL_Cand, global_Digits) > NormalizeDouble(mOrderStopLoss, global_Digits) )  {
                     // 損切値の制約を満たしていること　＝ long_SL_Cand < mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT
                     if(NormalizeDouble(long_SL_Cand, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        mFlag =OrderModify(mTicket, mOpen, long_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_LONG);
                        if(mFlag != true) {
                           printf( "[%d]FRACエラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]FRACエラー mOrderStopLoss=%s  long_SL_Cand=%s " , __LINE__,DoubleToStr(mOrderStopLoss), DoubleToStr(long_SL_Cand));
                           printf( "[%d]FRACエラー mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                           
                           ret = false;
                        }
                        else {

                        }
                     }  // 損切値の制約を満たしていること
                  } // long_SL_Candは、1つ前の谷＞2つ前の谷を満たす値が設定されていて、現時点の損切値より条件が良い
               }
               // ショートの場合の損切更新
               else if(mBuySell == OP_SELL) {
                  // 注目しているOrderが、エントリー直後(損切値が0.0)の時は、
                  //| ・エントリー直後(損切値が0.0)に、直前の山をストップとする。 
                  //|  ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、損切値を設定しない。
                  if(mOrderStopLoss <= 0.0) {
                     // 冒頭で、2つ前の山より直前の山が低い場合のみ、ショートのストップを直前の山を更新候補short_SL_Candにしている。
                     if(NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // short_SL_Candを使って損切値を更新できるので、そのまま。
                     }
                     else {
                        // short_SL_Candが制約により設定できないため、制約を満たす直近の山を探す。
                        // 見つからなければ、設定もれを防ぐため、制約を満たす値を設定する。
                        double buf_short_SL_Cand = NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble((1+mMarketinfoMODE_STOPLEVEL) * mMarketinfoMODE_POINT, global_Digits);
                        buf_short_SL_Cand = get_Next_Upper_FRAC(global_Symbol,     // 通貨ペア
                                                                global_Period,     // タイムフレーム 
                                                                mFractals_UPPER1_x, // このシフト＋１以上のシフトでFractalを計算する。
                                                                buf_short_SL_Cand  // この値より小さな値を探す
                                                              );
                        if(buf_short_SL_Cand > DOUBLE_VALUE_MIN) {
                          // 設定可能な次の山を見つけた。
                           short_SL_Cand = buf_short_SL_Cand;
                        }
                        else {
                          // 設定可能な最小値を損切値に設定していたが、性能が悪すぎた。
                          // 山から計算される損切値以外は設定しない。
                        }
                     }

                     // ショートではじめて損切設定する際の更新処理
                     if(short_SL_Cand > 0.0 &&
                        (NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits))
                     ) {
                        mFlag =OrderModify(mTicket, mOpen, short_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_SHORT);
                        if(mFlag != true) {
                           printf( "[%d]FRACエラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]FRACエラー mOrderStopLoss=%s  short_SL_Cand=%s " , __LINE__,DoubleToStr(mOrderStopLoss), DoubleToStr(short_SL_Cand));
                           printf( "[%d]FRACエラー mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                           ret = false;
                        }
                     }
                  }  //  if(mOrderStopLoss <= 0.0
                  // mOrderStopLossが設定済みの場合、
                  // 冒頭で、2つ前の山より直前の山が低い場合のみ、ショートのストップを直前の山を更新候補short_SL_Candにしている。
                  // mOrderStopLoss > 0.0 かつ 	short_SL_Cand < mOrderStopLoss ＝　より有利な損切値であること
                  else if(mOrderStopLoss > 0.0
                          && short_SL_Cand > 0.0 
                          && NormalizeDouble(short_SL_Cand, global_Digits) < NormalizeDouble(mOrderStopLoss, global_Digits) ) {
                     // 損切値の制約を満たしていること　＝ short_SL_Cand > mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT
                     if(  NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {  
                        mFlag =OrderModify(mTicket, mOpen, short_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_SHORT);
                        if(mFlag != true) {
                           printf( "[%d]FRACエラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]FRACエラー mOrderStopLoss=%s  short_SL_Cand=%s " , __LINE__,DoubleToStr(mOrderStopLoss), DoubleToStr(short_SL_Cand));
                           printf( "[%d]FRACエラー mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                           ret = false;
                        }
                     }
                  }
               }
            }
         }
      }
   }

   return ret;
}


//
// 関数update_AllOrdersSLFracのマジックナンバー無し版
// 精度を高めるため、引数にマジックナンバーのある別版を使うこと
// 
bool update_AllOrdersSLFrac(string mSymbol,             // 更新対象とする取引の通貨ペア
                            string mStrategy,           // 更新対象とする取引の戦略名。コメント欄に該当する。
                            st_Fractal &m_st_Fractals[] // 更新時点のフラクタル値
) {
   double mFractals_UPPER1_y      = 0.0; // 直近のフラクタル値(UPPER)
   int    mFractals_UPPER1_x      = 0;   // 直近のフラクタル値(UPPER)のシフト値
   datetime mFractals_UPPER1_time = 0;   // フラクタルを取得したシフト値のTime

   double mFractals_UPPER2_y      = 0.0; // 2つ目のフラクタル値(UPPER)
   int    mFractals_UPPER2_x      = 0;   // 2つ目のフラクタル値(UPPER)のシフト値
   datetime mFractals_UPPER2_time = 0;   // フラクタルを取得したシフト値のTime

   double mFractals_UPPER3_y      = 0.0; // 2つ目のフラクタル値(UPPER)
   int    mFractals_UPPER3_x      = 0;   // 2つ目のフラクタル値(UPPER)のシフト値
   datetime mFractals_UPPER3_time = 0;   // フラクタルを取得したシフト値のTime

   double mFractals_LOWER1_y      = 0.0; // 直近のフラクタル値(LOWER)
   int    mFractals_LOWER1_x      = 0;   // 直近のフラクタル値(LOWER)のシフト値
   datetime mFractals_LOWER1_time = 0;   // フラクタルを取得したシフト値のTime

   double mFractals_LOWER2_y      = 0.0; // 2つ目のフラクタル値(LOWER)
   int    mFractals_LOWER2_x      = 0;   // 2つ目のフラクタル値(LOWER)のシフト値
   datetime mFractals_LOWER2_time = 0;   // フラクタルを取得したシフト値のTime   

   double mFractals_LOWER3_y      = 0.0; // 2つ目のフラクタル値(LOWER)
   int    mFractals_LOWER3_x      = 0;   // 2つ目のフラクタル値(LOWER)のシフト値
   datetime mFractals_LOWER3_time = 0;   // フラクタルを取得したシフト値のTime  

   int i = 0;
   bool ret = true;
   double long_SL_Cand = 0.0;  // ロングの損切値候補
   double short_SL_Cand = 0.0; // ショートの損切値候補
   int mFlag = -1;             // OederModifyの返り値

   // 直前Fractalに値が無い場合は、Fractalを再計算する。
   if(m_st_Fractals[0].calcTime <= 0) {  
      // フラクタルの値を取得し、構造体st_Fractalsに入れる。
      bool flag_getFrac = get_Fractals(m_st_Fractals);
      if(flag_getFrac == false) {
         return false;
      }
   }

   read_FracST_TO_Param(m_st_Fractals,
                        mFractals_UPPER1_y,      //直近のフラクタル値(UPPER)
                        mFractals_UPPER1_x,      //直近のフラクタル値(UPPER)のシフト値
                        mFractals_UPPER1_time,   // フラクタルを取得したシフト値のTime

                        mFractals_UPPER2_y,      //2つ目のフラクタル値(UPPER)
                        mFractals_UPPER2_x,      //2つ目のフラクタル値(UPPER)のシフト値
                        mFractals_UPPER2_time,   // フラクタルを取得したシフト値のTime

                        mFractals_UPPER3_y,      //2つ目のフラクタル値(UPPER)
                        mFractals_UPPER3_x,      //2つ目のフラクタル値(UPPER)のシフト値
                        mFractals_UPPER3_time,   // フラクタルを取得したシフト値のTime

                        mFractals_LOWER1_y,      //直近のフラクタル値(LOWER)
                        mFractals_LOWER1_x,      //直近のフラクタル値(LOWER)のシフト値
                        mFractals_LOWER1_time,   // フラクタルを取得したシフト値のTime

                        mFractals_LOWER2_y,      //2つ目のフラクタル値(LOWER)
                        mFractals_LOWER2_x,      //2つ目のフラクタル値(LOWER)のシフト値
                        mFractals_LOWER2_time,   // フラクタルを取得したシフト値のTime   

                        mFractals_LOWER3_y,      //2つ目のフラクタル値(LOWER)
                        mFractals_LOWER3_x,      //2つ目のフラクタル値(LOWER)のシフト値
                        mFractals_LOWER3_time  // フラクタルを取得したシフト値のTime 
   );



/*
printf( "[%d]FRAC UPPER1_y=%s x=%d t=%s" , __LINE__,
   DoubleToStr(Fractals_UPPER1_y, global_Digits),
   Fractals_UPPER1_x,
   TimeToStr(Fractals_UPPER1_time));
   
printf( "[%d]FRAC UPPER2_y=%s x=%d t=%s" , __LINE__,
   DoubleToStr(Fractals_UPPER2_y, global_Digits),
   Fractals_UPPER2_x,
   TimeToStr(Fractals_UPPER2_time));
     
printf( "[%d]FRAC LOWER1_y=%s x=%d t=%s" , __LINE__,
   DoubleToStr(Fractals_LOWER1_y, global_Digits),
   Fractals_LOWER1_x,
   TimeToStr(Fractals_LOWER1_time));

printf( "[%d]FRAC LOWER2_y=%s x=%d t=%s" , __LINE__,
   DoubleToStr(Fractals_LOWER2_y, global_Digits),
   Fractals_LOWER2_x,
   TimeToStr(Fractals_LOWER2_time));
*/
   
   int LastMountORBottom = FRAC_NONE; // 直近がフラクタルの山FRAC_MOUNTか谷FRAC_BOTTOMか。
   if(mFractals_UPPER1_time > mFractals_LOWER1_time && mFractals_LOWER1_time > 0) { //山の方が、将来
      LastMountORBottom = FRAC_MOUNT;
   }
   else if(mFractals_UPPER1_time < mFractals_LOWER1_time && mFractals_UPPER1_time > 0) { //山の方が、過去
      LastMountORBottom = FRAC_BOTTOM;
   }
   else {
      LastMountORBottom = FRAC_NONE;
/*       printf( "[%d]FRAC FRACの直前の山と谷を判断できない。　UPPER1=%s=%d--%s LOWER1=%s=%d-%s 【参考】UPPER2=%s=%d-%s LOWER2=%s=%d-%s" , __LINE__,
               TimeToStr(mFractals_UPPER1_time), mFractals_UPPER1_time, DoubleToStr(mFractals_UPPER1_y, global_Digits),
               TimeToStr(mFractals_LOWER1_time), mFractals_LOWER1_time, DoubleToStr(mFractals_LOWER1_y, global_Digits),
               TimeToStr(mFractals_UPPER2_time), mFractals_UPPER2_time, DoubleToStr(mFractals_UPPER2_y, global_Digits),
               TimeToStr(mFractals_LOWER2_time), mFractals_LOWER2_time, DoubleToStr(mFractals_LOWER2_y, global_Digits)
      );*/

      return false;
   }
   


   // 直近がFracの谷であれば、ロングの損切値候補を計算する。
   // 2つ前の谷より直前の谷が高い場合のみ、ロングのストップを直前の谷にする。 
   if( (LastMountORBottom == FRAC_BOTTOM) 
        && (NormalizeDouble(mFractals_LOWER1_y, global_Digits) > NormalizeDouble(mFractals_LOWER2_y, global_Digits) && mFractals_LOWER2_y > 0.0)) {
         long_SL_Cand = mFractals_LOWER1_y;
   }
   // 直近がFracの山であれば、ショートの損切値候補を計算する。
   // 2つ前の山より直前の山が低い場合のみ、ショートのストップを直前の山にする。
   else if( (LastMountORBottom == FRAC_MOUNT)
             && (NormalizeDouble(mFractals_UPPER1_y, global_Digits) < NormalizeDouble(mFractals_UPPER2_y, global_Digits) && mFractals_UPPER1_y > 0.0)) {
         short_SL_Cand = mFractals_UPPER1_y;
        
   }
   else {
      ret = false;
   }


   // 口座情報を取得する。
   double mMarketinfoMODE_ASK = MarketInfo(mSymbol,MODE_ASK);
   double mMarketinfoMODE_BID = MarketInfo(mSymbol,MODE_BID);
   double mMarketinfoMODE_POINT = global_Points;
   double mMarketinfoMODE_STOPLEVEL = global_StopLevel;



   for(i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
            if(StringCompare(OrderSymbol(),mSymbol) == 0 
               && StringFind(OrderComment(), mStrategy, 0) >= 0) {
               int    mTicket          = OrderTicket();
               double mOpen            = OrderOpenPrice();
               double mOrderStopLoss   = OrderStopLoss();
               double mOrderTakeProfit = OrderTakeProfit();
               int mBuySell            = OrderType();
    
               // ロングの場合の損切更新
               if(mBuySell == OP_BUY) {
                  // 注目しているOrderが、エントリー直後(損切値が0.0)の時は、
                  // ・エントリー直後(損切値が0.0)に、直前の谷をストップとする。 
                  // ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、損切値を設定しない。 
                  if(mOrderStopLoss <= 0.0) {
                     // 冒頭で、2つ前の谷より直前の谷が高い場合のみ、ロングのストップを直前の谷を更新候補long_SL_Candにしていれば、その値を設定できるか調べる。
                     if(long_SL_Cand > 0.0 && NormalizeDouble(long_SL_Cand, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // long_SL_Candを使って損切値を更新できるので、そのまま。
                     }
                     else { 
                       // long_SL_Candが制約により設定できないため、制約を満たす直近の谷を探す。
                       // 見つからなければ、設定もれを防ぐため、制約を満たす値を設定する。
                       double buf_long_SL_Cand = NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble((1+mMarketinfoMODE_STOPLEVEL) * mMarketinfoMODE_POINT, global_Digits);
                       buf_long_SL_Cand = get_Next_Lower_FRAC(global_Symbol,     // 通貨ペア
                                                              global_Period,     // タイムフレーム 
                                                              mFractals_LOWER1_x, // このシフト＋１以上のシフトでFractalを計算する。
                                                              buf_long_SL_Cand   // この値より小さな値を探す
                                                              );
                       if(buf_long_SL_Cand > DOUBLE_VALUE_MIN) {
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
                           printf( "[%d]FRACエラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]FRACエラー mOrderStopLoss=%s  long_SL_Cand=%s " , __LINE__,DoubleToStr(long_SL_Cand), DoubleToStr(mOrderTakeProfit));
                           printf( "[%d]FRACエラー mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                        
                           ret = false;
                        }
                        else {
                        }
                     }
                  }  // if(mOrderStopLoss <= 0.0) {
                  
                  // mOrderStopLossが設定済みの場合、
                  // 冒頭で、2つ前の谷より直前の谷が高い場合のみ、ロングのストップを直前の谷を更新候補long_SL_Candにしていれば、
                  // mOrderStopLoss > 0.0 かつ long_SL_Cand > mOrderStopLoss ＝　より有利な損切値であること
                  else if( mOrderStopLoss > 0.0 
                          && long_SL_Cand > 0.0 
                          && NormalizeDouble(long_SL_Cand, global_Digits) > NormalizeDouble(mOrderStopLoss, global_Digits) )  {
                     // 損切値の制約を満たしていること　＝ long_SL_Cand < mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT
                     if(NormalizeDouble(long_SL_Cand, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        mFlag =OrderModify(mTicket, mOpen, long_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_LONG);
                        if(mFlag != true) {
                           printf( "[%d]FRACエラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]FRACエラー mOrderStopLoss=%s  long_SL_Cand=%s " , __LINE__,DoubleToStr(mOrderStopLoss), DoubleToStr(long_SL_Cand));
                           printf( "[%d]FRACエラー mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                           
                           ret = false;
                        }
                        else {

                        }
                     }  // 損切値の制約を満たしていること
                  } // long_SL_Candは、1つ前の谷＞2つ前の谷を満たす値が設定されていて、現時点の損切値より条件が良い
               }
               // ショートの場合の損切更新
               else if(mBuySell == OP_SELL) {
                  // 注目しているOrderが、エントリー直後(損切値が0.0)の時は、
                  //| ・エントリー直後(損切値が0.0)に、直前の山をストップとする。 
                  //|  ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、損切値を設定しない。
                  if(mOrderStopLoss <= 0.0) {
                     // 冒頭で、2つ前の山より直前の山が低い場合のみ、ショートのストップを直前の山を更新候補short_SL_Candにしている。
                     if(NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // short_SL_Candを使って損切値を更新できるので、そのまま。
                     }
                     else {
                        // short_SL_Candが制約により設定できないため、制約を満たす直近の山を探す。
                        // 見つからなければ、設定もれを防ぐため、制約を満たす値を設定する。
                        double buf_short_SL_Cand = NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble((1+mMarketinfoMODE_STOPLEVEL) * mMarketinfoMODE_POINT, global_Digits);
                        buf_short_SL_Cand = get_Next_Upper_FRAC(global_Symbol,     // 通貨ペア
                                                                global_Period,     // タイムフレーム 
                                                                mFractals_UPPER1_x, // このシフト＋１以上のシフトでFractalを計算する。
                                                                buf_short_SL_Cand  // この値より小さな値を探す
                                                              );
                        if(buf_short_SL_Cand > DOUBLE_VALUE_MIN) {
                          // 設定可能な次の山を見つけた。
                           short_SL_Cand = buf_short_SL_Cand;
                        }
                        else {
                          // 設定可能な最小値を損切値に設定していたが、性能が悪すぎた。
                          // 山から計算される損切値以外は設定しない。
                        }
                     }

                     // ショートではじめて損切設定する際の更新処理
                     if(short_SL_Cand > 0.0 &&
                        (NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits))
                     ) {
                        mFlag =OrderModify(mTicket, mOpen, short_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_SHORT);
                        if(mFlag != true) {
                           printf( "[%d]FRACエラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]FRACエラー mOrderStopLoss=%s  short_SL_Cand=%s " , __LINE__,DoubleToStr(mOrderStopLoss), DoubleToStr(short_SL_Cand));
                           printf( "[%d]FRACエラー mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                           ret = false;
                        }
                     }
                  }  //  if(mOrderStopLoss <= 0.0
                  // mOrderStopLossが設定済みの場合、
                  // 冒頭で、2つ前の山より直前の山が低い場合のみ、ショートのストップを直前の山を更新候補short_SL_Candにしている。
                  // mOrderStopLoss > 0.0 かつ 	short_SL_Cand < mOrderStopLoss ＝　より有利な損切値であること
                  else if(mOrderStopLoss > 0.0
                          && short_SL_Cand > 0.0 
                          && NormalizeDouble(short_SL_Cand, global_Digits) < NormalizeDouble(mOrderStopLoss, global_Digits) ) {
                     // 損切値の制約を満たしていること　＝ short_SL_Cand > mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT
                     if(  NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {  
                        mFlag =OrderModify(mTicket, mOpen, short_SL_Cand, mOrderTakeProfit, 0, LINE_COLOR_SHORT);
                        if(mFlag != true) {
                           printf( "[%d]FRACエラー OrderModify：：%s" , __LINE__,GetLastError());
                           printf( "[%d]FRACエラー mOrderStopLoss=%s  short_SL_Cand=%s " , __LINE__,DoubleToStr(mOrderStopLoss), DoubleToStr(short_SL_Cand));
                           printf( "[%d]FRACエラー mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT=%s" , __LINE__,DoubleToStr(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                           ret = false;
                        }
                     }
                  }
               }
            }
      }
   }

   return ret;
}



