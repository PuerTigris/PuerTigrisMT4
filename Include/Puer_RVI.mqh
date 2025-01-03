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




//+------------------------------------------------------------------+
//|95.RVI                                                 　　　   |
//+------------------------------------------------------------------+

int entryRVI() {
   //変数
   //現在の値
   double now_rvi;         //RVI
   double now_signal;      //シグナル
   double now_rvi_1min;
   double now_signal_1min;
   
   //１ティック前の値
   double before_rvi;      //RVI
   double before_signal;   //シグナル
   double before_rvi_1min;      //RVI
   double before_signal_1min;   //シグナル

   //現在値取得
   //RVI
   now_rvi      = iRVI(NULL,          // 通貨ペア
                        PERIOD_CURRENT,// 時間軸
                        average_period,// 計算をする平均期間
                        MODE_MAIN,     // ラインインデックス。MODE_MAIN＝ベースライン、MODE_SIGNAL＝シグナルライン
                        0              // シフト
                        );
   now_rvi_1min = iRVI(NULL,PERIOD_MN1,average_period,MODE_MAIN,0);

   //シグナル
   now_signal      = iRVI(NULL,PERIOD_CURRENT,average_period,MODE_SIGNAL,0);
   now_signal_1min = iRVI(NULL,PERIOD_MN1,average_period,MODE_SIGNAL,0);


   //1ティック前の情報取得
   //RVI
   before_rvi      = iRVI(NULL,PERIOD_CURRENT,average_period,MODE_MAIN,1);
   before_rvi_1min = iRVI(NULL,PERIOD_MN1,average_period,MODE_MAIN,1);

   //シグナル
   before_signal      = iRVI(NULL,PERIOD_CURRENT,average_period,MODE_SIGNAL,1);
   before_signal_1min = iRVI(NULL,PERIOD_MN1,average_period,MODE_SIGNAL,1);


   //★ボリンジャーバンド２σ上下の差が引数以上の時trueを返す。
   bool check_bb_band2 = check_BB_bands2_width(Sigma2_Min_Width_POINT);


   //順張り
   //ボラティリティ拡大なのでロング=RVIがマイナスからプラスに変わったタイミングでロング
   if(before_signal < 0 
      && now_signal >= 0 
      && check_bb_band2 == true){

      return BUY_SIGNAL;
   } 

   //ボラティリティ縮小なのでショート=RVIがプラスからマイナスに変わったタイミングでロング
      if(before_signal > 0 
         && now_signal <= 0 
         && check_bb_band2 == true){ 

      return SELL_SIGNAL;
   } 

   //逆張り   
   //メインとシグナルのゴールデンクロスでロング
   if( (before_signal > before_rvi) //１ティック前がシグナルのほうが大きい
       && (now_signal <= now_rvi)   //クロス
     ){

      return BUY_SIGNAL;
   }

   //メインとシグナルのデッドクロスでショート
   if ( (before_signal < before_rvi)  //１ティック前がメインのほうが大きい？ 
         && (now_signal >= now_rvi)    //クロス
      ){

      return SELL_SIGNAL;

   }
   
   return NO_SIGNAL;
}


//+------------------------------------------------------------------+ 
//| ボリンジャーバンド幅のチェック 
//| 引数の指定値mWidth以上の場合 trueを返す | 
//+------------------------------------------------------------------+ 
bool check_BB_bands2_width(double mWidth){ 
bool my_ret = false; 
//2σボリンジャーバンド 
double bb_2 = iBands(NULL,PERIOD_CURRENT,20,2,0,PRICE_CLOSE,1,0); 
//-2σボリンジャーバンド 
double bb_M2 = iBands(NULL,PERIOD_CURRENT,20,2,0,PRICE_CLOSE,2,0); 
//バンド幅計算
double bb_haba = bb_2 - bb_M2; 

if(bb_haba > mWidth){
   my_ret = true;      
}

return my_ret;
}