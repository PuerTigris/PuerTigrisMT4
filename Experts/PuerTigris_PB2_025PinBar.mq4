// 20221120
// ALLOWABLE_DIFF_PERとPING_WEIGHT_MINSの削除
//
//20221029
// 20220606PinBarのみのEAとして、新規作成
// 20220901仮想最適化機能を追加
//
//
// 20220928仮想取引の約定に使わない次の項目は、パラメータセットから除外する。
// PING_WEIGHT_MINSは、最適化の項目とせず、２か３固定とする。
// ・PING_WEIGHT_MINS
// ・VTRADEBACKSHIFTNUM
/*
このMQL4プログラムは、ピンバー（Pin Bar）というローソク足パターンを検知して取引を行う自動売買EA（Expert Advisor）です。さらに、仮想取引による最適化機能を持ち、バックテストで得られた最適なパラメータを用いて実取引を行う機能も備えています。

以下に、プログラムの内容、売買戦略、改善点について詳しく解説します。

プログラム概要

ピンバー検出:

Puer_PinBAR.mqhというインクルードファイルを利用して、ピンバーを検出します。ピンバーとは、実体が小さく、長いヒゲを持つローソク足のことです。

ピンバーの定義は、G_PinBarMethod、G_PinBarTimeframe、G_PinBarBackstep、G_PinBarBODY_MIN_PER、G_PinBarPIN_MAX_PERといった外部パラメータで調整できます。

トレーディングライン:

Tigris_TradingLine.mqhというインクルードファイルを用いて、過去の最高値・最安値を元にしたトレーディングライン（サポート・レジスタンスライン）を計算します。

トレーディングラインは、エントリーの際のフィルタとして機能します。

実取引:

ピンバーが検出された場合、entryPinBar()関数で、トレーディングラインの範囲内で、買いまたは売りの注文を発注します。

発注時には、TP_PIPS（利確幅）、SL_PIPS（損切幅）を設定できます。また、FLOORING（損切値の切り上げ機能）も設定可能です。

仮想取引:

Tigris_VirtualTrade.mqhというインクルードファイルを用いて、仮想取引を行います。

仮想取引は、複数のパラメータセットを用いてバックテストを行い、最もパフォーマンスの高いパラメータセットを特定するために利用します。

SWITCH_USE_OPTIMIZERをtrueにすると有効になります。

パラメータ最適化:

仮想取引の結果（損益、プロフィットファクター、取引数など）を分析し、calc_OptimizedParameterSet()関数で、最適なパラメータセットを選択します。

最適化の条件は、OPT_MIN_TRADENUM（最小取引数）、WINNING_PER_LOSE_RATE_MIN（勝ち数/負け数）、PROFITFACTOR_MIN（プロフィットファクター）といった外部パラメータで設定します。

ファイル入出力:

仮想取引の結果や、設定したパラメータセットをCSVファイルとして出力できます。

write_vOrders_025PinBAR()関数で仮想取引データを、write_st_25PinOptParams()関数でパラメータセットを出力します。

これにより、バックテスト結果を分析したり、最適化されたパラメータセットを保存したりできます。
*/


//+------------------------------------------------------------------+	
//|  Copyright (c) 2016 トラの親 All rights reserved.                |	
//|                                                                  |
//+------------------------------------------------------------------+	
#property copyright "Copyright (c) 2016 トラの親 All rights reserved."				
#property link      "http://nenshuuha.blog.fc2.com/"						
//+------------------------------------------------------------------+	
//| ヘッダーファイル読込                                             |	
//+------------------------------------------------------------------+	
#include <stderror.mqh>	
#include <stdlib.mqh>	
#include <Tigris_COMMON.mqh>
#include <Tigris_VirtualTrade.mqh>
#include <Tigris_TradingLine.mqh>

#include <Puer_PinBAR.mqh>	 
//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
//
// 仮想最適化利用バージョンの共通
//
extern bool   SWITCH_USE_OPTIMIZER = false;

//
// 025PinBar専用
//
extern string PuerTigrisPBTitle    = "---PBのパラメータ---";
extern int    MagicNumberPB        = 90000025;
extern int    G_PinBarMethod       = 1;   // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5, 110(6)=No3とNo5, 111=No1とNo3とNo5  
int           G_PinBarTimeframe    = 0;     // ピンの計算に使う時間軸
extern int    G_PinBarBackstep     = 10;    // 大陽線、大陰線が発生したことを何シフト前まで確認するか
extern double G_PinBarBODY_MIN_PER = 60.0;  // 実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
extern double G_PinBarPIN_MAX_PER  = 10.0;  // 実体が髭のナンパ―セント以下であればピンと判断するか
input bool   TRADE_PLUS_SWAP = true;


//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
//
// 仮想最適化利用バージョンの共通
//
string PGName = "PuerTigris"; //プログラム名				
// bool   global_flag_StopTradeUpper = false;
// bool   global_flag_StopTradeLower = false;
 
int    OPT_MIN_TRADENUM = 5;            // パラメータセット選定用。最適化の実行に必要な仮想取引数の最小値。この件数以上のパラメータセットが選定対象。通常は、5
double WINNING_PER_LOSE_RATE_MIN = 1.25; // パラメータセット選定用。パラメータセット別の勝ち数÷負け数がこの値以上をパラメータセットが選定対象。通常は、1.0
double PROFITFACTOR_MIN = 1.01;         // パラメータセット選定用。プロフィットファクターがこの値以上のパラメータセットが選定対象。通常は、1.01
//
// 025PinBar専用
//
datetime PBtime0 = 0;                                  //　EAが大量のオーダーを重複して出力するのを避けるための変数。
st_25PinOptParam st_25PinOptParams[VOPTPARAMSNUM_MAX]; // 仮想取引データ。st_25PinOptParams[0]に現在設定中の外部パラメータをセットする。
st_25PinOptParam optimized_st_25PinOptParams;          // 仮想取引データ。st_25PinOptParams[0]に現在設定中の外部パラメータをセットする。


datetime CONTROLALLtime0 = 0;//足1本で1回の処理をするための変数

st_25PinOptParam Default_st_25PinOptParams;


//+------------------------------------------------------------------+	
//| 初期処理                                                         |	
//+------------------------------------------------------------------+	
int init() {	
   //オブジェクトの削除	
   MyObjectsDeleteAll();

   updateExternalParamCOMM();
   updateExternalParam_TradingLine();
   
   // 初期状態の外部パラメータをグローバル変数にコピーする。
   update_GlobalParam_to_ExternalParam();
   
   // テスト状態を判定して、start()内では画面処理をしないようにする
   global_IsTesting = IsTesting() ;
   if (global_IsTesting == true) {
   }
   else {
      bool result_flag       = false;                            //処理結果格納用   
      int err_code           = 0;                                //エラーコード取得用				      
      string err_title       = "[オブジェクト生成エラー] ";      //エラーメッセージタイトル
      //画面にＥＡ名を表示させる。
      //ラベルオブジェクト生成(PGName)	
      if(ObjectFind("PGName")!=WindowOnDropped())	{	
         result_flag = ObjectCreate("PGName",OBJ_LABEL,WindowOnDropped(),0,0);	
         if(result_flag == false)  {	
            err_code = GetLastError();	
            printf( "[%d]エラー DB未接続:：%s---%s" , __LINE__ , err_title, ErrorDescription(err_code));
         }	
      }	
      ObjectSet("PGName",OBJPROP_CORNER,3);              //アンカー設定	
      ObjectSet("PGName",OBJPROP_XDISTANCE,3);           //横位置設定	
      ObjectSet("PGName",OBJPROP_YDISTANCE,5);           //縦位置設定	
      ObjectSetText("PGName",PGName,8,"Arial",Gray);     //テキスト設定	
   }

   // 現在のシフトでトレーディングラインを計算する
   bool flag_calc_TradingLines = calc_TradingLines(global_Symbol, 
                                                   TIME_FRAME_MAXMIN, 
                                                   SHIFT_SIZE_MAXMIN, 
                                                   g_past_max, 
                                                   g_past_maxTime, 
                                                   g_past_min, 
                                                   g_past_minTime, 
                                                   g_past_width, 
                                                   g_long_Min, 
                                                   g_long_Max, 
                                                   g_short_Min, 
                                                   g_short_Max);

   if(flag_calc_TradingLines == false) {
  	   return -1;
   }
 
   if(SWITCH_USE_OPTIMIZER == true) {
      init_Virtual_Optimize_Env();
   }

   return(INIT_SUCCEEDED);	
}	
	
//+------------------------------------------------------------------+	
//| 終了処理                                                         |	
//+------------------------------------------------------------------+	
int deinit() {	
   if(SWITCH_USE_OPTIMIZER == true && VT_FILEIO_FLAG == true) {
      output_st_vOrders();

      string bufTime = TimeToStr(TimeLocal());
      StringReplace(bufTime, ".", "_");
      StringReplace(bufTime, ":", "_");
      string bufFileName = "testdeinit" + bufTime + ".csv";
printf( "[%d]PB deinit：出力ファイル名=%s" , __LINE__ , bufFileName);      
      write_vOrders_025PinBAR(bufFileName);
      output_vOrderPLs(st_vOrderPLs);
      write_vOrderPLs(st_vOrderPLs);

      bufTime = TimeToStr(TimeLocal());
      StringReplace(bufTime, ".", "_");
      StringReplace(bufTime, ":", "_");
      bufFileName = "deinit時" + bufTime + ".csv";
      write_st_25PinOptParams(bufFileName, bufTime);
      
      write_vOrders_025PinBAR("vOrdersALLPIN.csv");
   }
   else if(SWITCH_USE_OPTIMIZER == true && VT_FILEIO_FLAG == false) {
   
      output_st_vOrders();
      create_st_vOrderPLs(TimeCurrent());
      output_vOrderPLs(st_vOrderPLs);
   } 

   //オブジェクトの削除	
   MyObjectsDeleteAll();

   return(0);	
}	
	
//+------------------------------------------------------------------+	
//| メイン処理                                                       |	
//+------------------------------------------------------------------+	
int start()	
{
   if(checkExternalParam() != true) {
      printf( "[%d]エラー 外部パラメーターに不適切な値あり" , __LINE__);
      return -1;
   }

   //変数宣言　　	
   bool result_flag       = false;                            //処理結果格納用   
   int type               = OP_BUY;                           //売買区分   
   string comment         = "";                               //オーダーコメント格納用				   
   color arrow_color      = CLR_NONE;                         //色	   
   int i                  = 0;                                //汎用カウンタ   
   int x                  = 0;                                //汎用カウンタ   
   int err_code           = 0;                                //エラーコード取得用				      
   string err_title       = "[オブジェクト生成エラー] ";      //エラーメッセージタイトル			   
   string err_title02     = "[例外エラー] ";                  //エラーメッセージタイトル02			   
   int shift_value = 1;                                       //MAやCloseを計算するときのシフト値		
   
   datetime timeCurr = TimeCurrent();
   double tmpBID = 0.0;
   double tmpASK = 0.0;

   ShowTestMsg = false;

   // 処理を一定時間ごとにのみ行うためのフラグ設定
   // 例えば、ティックごとに行うと処理が重いので、１分おきに処理するなど。
   if(TimeCurrent() - CONTROLALLtime0 >= PERIOD_M1 * 60) { // 
      CONTROLALLtime0 = TimeCurrent();
   }
   else {
      return 1;
   }	

   //
   // トレーディングラインの更新
   //
   // BIDが過去最大値を超えた場合は、トレンドが大きく変わったと判断して、トレーディングラインを見直し
   tmpBID = NormalizeDouble(Bid, global_Digits);
   if(g_past_max > 0.0 
      && NormalizeDouble(g_past_max, global_Digits) < NormalizeDouble(tmpBID, global_Digits)) {  
      update_TradingLines(global_Symbol, 0, SHIFT_SIZE_MAXMIN);
   }

   // ASKが過去最小値を下回った場合は、トレンドが大きく変わったと判断して、トレーディングラインを見直し
   tmpASK = NormalizeDouble(Ask, global_Digits);
   if(g_past_min > 0.0 
      && NormalizeDouble(g_past_min, global_Digits) > NormalizeDouble(tmpASK, global_Digits)) {  
      update_TradingLines(global_Symbol, 0, SHIFT_SIZE_MAXMIN);        
   }
   //
   // 実取引のメモリ呼び出し
   //
   // 実行時点で未決済取引をグローバル変数に読み出す。
//printf( "[%d]PB read_OpenTrades実行" , __LINE__);   
//   read_OpenTrades(MagicNumberPB);
   

//
//
// 仮想取引は、実取引の後に行うこと。
//　直近の仮想取引の損益が、実取引実行前のパラメータセット選定に正しく反映されない。
// 具体的には、実行時点で新規発注した仮想取引は、将来的にどんなに大きな損失を出すとしても、
// 実取引用パラメータセット選定では損益０とみなされる。
//

   //
   // 【実取引】
   // 実取引をする際、この時点では、ロングかショートかは不明。しかし、オープン中の実取引の約定価格から判断して、
   // ロングもショートも共にできないのであれば、実取引をあきらめる。
   // 
   // 直近で発注した時間以外であれば、実取引を試す。
   if(PBtime0 != Time[0]) {
      // 
      // SWITCH_USE_OPTIMIZER == trueの時、パラメータセットの計算の上、書き換えをする。 
      // 
      if(SWITCH_USE_OPTIMIZER == true) {
         // 最適なパラメータセットを計算する
           string ret_optParamSet = calc_OptimizedParameterSet(optimized_st_25PinOptParams);  

printf( "[%d]PB ↓確認用↓" , __LINE__);
output_st_25PinOptParams(optimized_st_25PinOptParams);
printf( "[%d]PB ↑確認用↑" , __LINE__);

         // 最適なパラメータセットを上書きする
         // calc_OptimizedParameterSetで入手したパラメータセットの戦略名が"25PIN@@00001"などの場合
         if(StringFind(ret_optParamSet, g_StratName25) >= 0) {
            // 最適なパラメータセットoptimized_st_25PinOptParamsで、パラメータセットを上書きする処理
            overwrite_st_25PinOptParams(optimized_st_25PinOptParams);
            printf( "[%d]PB 採用したパラメータセット。%s" , __LINE__,optimized_st_25PinOptParams.strategyID);

// 仮想取引で変更したトレーディングラインを戻す
update_TradingLines(global_Symbol, 0, SHIFT_SIZE_MAXMIN);
          
            // 実取引を行う
            entryPinBar(MagicNumberPB);
   
            // 上書きしたパラメータセットを元に戻す。
            recovery_st_25PinOptParams();
// 仮想取引で変更したトレーディングラインを戻す
update_TradingLines(global_Symbol, 0, SHIFT_SIZE_MAXMIN);

         }

         //
         // いづれにも該当しない場合はデフォルト値を使う。
         //
         else {
            printf( "[%d]PB 条件を満たすパラメータセットが無かったため、デフォルトを採用する" , __LINE__);
            output_st_25PinOptParams(Default_st_25PinOptParams);
            // 最適なパラメータセットoptimized_st_25PinOptParamsで、パラメータセットを上書きする処理
            overwrite_st_25PinOptParams(Default_st_25PinOptParams);

            // 実取引を行う
            entryPinBar(MagicNumberPB);
    
            // 上書きしたパラメータセットを元に戻す。
            recovery_st_25PinOptParams();
         }
      } // if(SWITCH_USE_OPTIMIZER == true) {
      else if(SWITCH_USE_OPTIMIZER == false) {      
         entryPinBar(MagicNumberPB);
      }
   }  //   if(PBtime0 != Time[0]) {

   //
   // 【仮想取引】
   if(SWITCH_USE_OPTIMIZER == true) {
      // シフト０で、全パラメータセットを使った仮想取引を行う。
      // ※※※※※関数create_vTradeEachShift_25PINの中でパラメータセットを書き換えるので、
      // ※※※※※この関数実行前にパラメータセットの上書きをしないこと。
      create_vTradeEachShift_25PIN(g_StratName25,   // 戦略名。g_StratName25 = "25PIN@@00001"
                                   0,               // 仮想取引の約定日を取得するための時間軸
                                   0                // どのシフトで仮想取引を試みるか
                                   );
      // 仮想取引で変更したトレーディングラインを戻す
      update_TradingLines(global_Symbol, 0, SHIFT_SIZE_MAXMIN);

    }                

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、全オーダーの指値と逆指値をセットする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      update_AllOrdersTPSL(global_Symbol, MagicNumberPB, TP_PIPS, SL_PIPS);
   } 

   //最小利食値FLOORINGが設定されていれば、損切値の更新を試す。
   if(FLOORING >= 0) {
      flooringSL(global_Symbol, MagicNumberPB, FLOORING, FLOORING_CONTINUE);
   }

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、マジックナンバーをキーとして強制決済をする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      do_ForcedSettlement(MagicNumberPB, global_Symbol, TP_PIPS, SL_PIPS);
   } 
   return(0);	
}	
	

//
// 外部パラメータをグローバル変数にコピーする。
//
void update_GlobalParam_to_ExternalParam() {
   PinBarMethod       = G_PinBarMethod;       // 計算ロジック1～7
                                              // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5
                                              // 110(6)=No3とNo5, 111(7)=No1とNo3とNo5  
   PinBarTimeframe    = G_PinBarTimeframe;    // 計算に使う時間軸。1～9
   PinBarBackstep     = G_PinBarBackstep;     // 大陽線、大陰線が発生したことを何シフト前まで確認するか
   PinBarBODY_MIN_PER = G_PinBarBODY_MIN_PER; // 実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
   PinBarPIN_MAX_PER  = G_PinBarPIN_MAX_PER;  // 実体が髭のナンパ―セント以下であればピンと判断するか
}


//+------------------------------------------------------------------+
//| PinBar  PuerTigris026.mq4から抜粋                  　　　　      |
//+------------------------------------------------------------------+
bool entryPinBar(int mMagic){
   // 戦略別mqhの関数を呼ぶ前に、外部パラメータをグローバル変数にコピーする。
   update_GlobalParam_to_ExternalParam();						

   // 同時に多数発注するのを防ぐ。
   // datetime tradeTime = TimeLocal();
   datetime tradeTime = Time[0];
   if(PBtime0 == tradeTime) {
//   printf( "[%d]PB 実験として、return falseを削除中" , __LINE__);

//      return false;// -997
   }

   // 戦略別mqhの関数を使用する。
   
   int mSignal = entryPinBar();
//printf( "[%d]PB 確認　シグナルmSignal=%d   BUY=%d  SELL=%d" , __LINE__ ,mSignal, BUY_SIGNAL, SELL_SIGNAL);
   int intTrend = NoTrend;
   bool mFlag = false;
   double sl = 0.0;
   double tp = 0.0;
   int ticket_num = 0;
   
   bool flag_read_TradingLines;
   double   past_max;     // 過去の最高値
   datetime past_maxTime; // 過去の最高値の時間
   double   past_min;     // 過去の最安値
   datetime past_minTime; // 過去の最安値の時間
   double   past_width;   // 過去値幅。past_max - past_min
   double   long_Min;     // ロング取引を許可する最小値
   double   long_Max;     // ロング取引を許可する最大値
   double   short_Min;    // ショート取引を許可する最小値
   double   short_Max;    // ショート取引を許可する最大値   
   if(mSignal == BUY_SIGNAL || mSignal == SELL_SIGNAL) {
update_TradingLines(global_Symbol, 0, SHIFT_SIZE_MAXMIN);
   
      flag_read_TradingLines = read_TradingLines(past_max,  // 出力：過去の最高値
                                              past_maxTime,   // 出力：過去の最高値の時間
                                              past_min,       // 出力：過去の最安値
                                              past_minTime,   // 出力：過去の最安値の時間
                                              past_width,     // 出力：過去値幅。past_max - past_min
                                              long_Min,       // 出力：ロング取引を許可する最小値
                                              long_Max,       // 出力：ロング取引を許可する最大値
                                              short_Min,      // 出力：ショート取引を許可する最小値
                                              short_Max       // 出力：ショート取引を許可する最大値
                                            );  
/*printf( "[%d]PB 実取引のライン>>%s<< short_Max=%s short_Min=%s long_Max=%s long_Min=%s" , __LINE__ , TimeToStr(Time[0]),
DoubleToStr(short_Max, global_Digits),
DoubleToStr(short_Min, global_Digits),
DoubleToStr(long_Max, global_Digits),
DoubleToStr(long_Min, global_Digits)
);*/
                                            
   }

   double mMarketinfoMODE_ASK;
   double mMarketinfoMODE_BID;
   
   // トレーディングラインとENTRY_WIDTH_PIPSを使って、発注予定値が条件を満たすかどうかを判断する。
   // 発注不可の値であれば、シグナルをNO_SIGNALに変更する。
   bool flag_is_TradablePrice_EntryWidth;
   if( mSignal == BUY_SIGNAL) {
      mMarketinfoMODE_ASK = MarketInfo(global_Symbol,MODE_ASK);   
      flag_is_TradablePrice_EntryWidth = 
         is_TradablePrice_EntryWidth(mMagic,
                                     BUY_SIGNAL,
                                     long_Max,
                                     long_Min,
                                     ENTRY_WIDTH_PIPS,     // 何PIPSの間隔をあけるか
                                     mMarketinfoMODE_ASK); // 発注予定値
      if(flag_is_TradablePrice_EntryWidth == false) {
         mSignal = NO_SIGNAL;
      }
   }
   else if( mSignal == SELL_SIGNAL) {
      mMarketinfoMODE_BID = MarketInfo(global_Symbol,MODE_BID);
      flag_is_TradablePrice_EntryWidth = 
         is_TradablePrice_EntryWidth(mMagic,
                                     SELL_SIGNAL,
                                     short_Max,
                                     short_Min,
                                     ENTRY_WIDTH_PIPS,     // 何PIPSの間隔をあけるか
                                     mMarketinfoMODE_BID); // 発注予定値
      if(flag_is_TradablePrice_EntryWidth == false) {
/*printf( "[%d]PB 近い取引があるので売りシグナル取り消し %s short_Max=%s  short_Min=%s mMarketinfoMODE_BID=%s" , __LINE__ , TimeToStr(Time[0]),
DoubleToStr(short_Max, global_Digits),
DoubleToStr(short_Min, global_Digits),
DoubleToStr(mMarketinfoMODE_BID, global_Digits)
);*/
      
         mSignal = NO_SIGNAL;
      }
   }
   
   
   if( mSignal == BUY_SIGNAL) {

      tp = mMarketinfoMODE_ASK + NormalizeDouble(change_PiPS2Point(TP_PIPS), global_Digits); // 利確の候補
      sl = mMarketinfoMODE_ASK - NormalizeDouble(change_PiPS2Point(SL_PIPS), global_Digits); // 損切の候補 
printf( "[%d] mMarketinfoMODE_BID=%s change_PiPS2Point(TP_PIPS)=%s  change_PiPS2Point(SL_PIPS)=%s tp=%s sl=%s" , __LINE__ , 
         DoubleToStr(mMarketinfoMODE_ASK, global_Digits),
         DoubleToStr(change_PiPS2Point(TP_PIPS), global_Digits),
         DoubleToStr(change_PiPS2Point(SL_PIPS), global_Digits),
         DoubleToStr(tp, global_Digits),
         DoubleToStr(sl, global_Digits)
         
);   
      ticket_num = mOrderSend5(global_Symbol,OP_BUY,LOTS,mMarketinfoMODE_ASK,SLIPPAGE, sl, tp,changeMagicToString(mMagic),mMagic,0, LINE_COLOR_LONG);	
      if(ticket_num > 0){
   
printf( "[%d] チケット番号=%d OrderTick=%d　　　コメント=***%s***" , __LINE__ , ticket_num, OrderTicket(), OrderComment());      
         PBtime0 = tradeTime;
      }
      else if(ticket_num == ERROR_ORDERSEND) {
         printf( "[%d]エラー 買い発注の失敗::%d" , __LINE__ , ticket_num);
         return false;
      } 
   }
   else if(mSignal == SELL_SIGNAL) {
      tp = mMarketinfoMODE_BID - NormalizeDouble(change_PiPS2Point(TP_PIPS), global_Digits); // 利確の候補
      sl = mMarketinfoMODE_BID + NormalizeDouble(change_PiPS2Point(SL_PIPS), global_Digits); // 損切の候補 
printf( "[%d] mMarketinfoMODE_BID=%s change_PiPS2Point(TP_PIPS)=%s  tp=%s sl=%s" , __LINE__ , 
         DoubleToStr(mMarketinfoMODE_BID, global_Digits),
         DoubleToStr(change_PiPS2Point(TP_PIPS)),
         DoubleToStr(tp, global_Digits),
         DoubleToStr(sl, global_Digits)
         
);      
      
      ticket_num = mOrderSend5(global_Symbol,OP_SELL,LOTS,mMarketinfoMODE_BID,SLIPPAGE,sl, tp,changeMagicToString(mMagic),mMagic,0,LINE_COLOR_SHORT);
      if(ticket_num > 0) {
printf( "[%d] コメント=***%s***" , __LINE__ , OrderComment());      
      
         PBtime0 = tradeTime;
      }
      else if(ticket_num == ERROR_ORDERSEND) {
         printf( "[%d]エラー 売り発注の失敗::%d" , __LINE__ , ticket_num);
         return false;
      } 
   }
   else {
      return false;
   }
   return true;
}







//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|   共通関数　　　                                                 |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|   定時メール送信                                                 |
//+------------------------------------------------------------------+	
// 利用していないため、void SendMailOrg(int mailtime1, int mailtime2)を削除
// 作成する場合は、OpenTrade_BuySell[MAX_TRADE_NUM];を使うこと。

//+------------------------------------------------------------------+
//| マジックナンバー（数値）を戦略名（文字列）に変換する　　　                     　　　　　      |
//+------------------------------------------------------------------+
string changeMagicToString(int mag) {
   string strBuf = "";
if(mag == MagicNumberPB) {
         strBuf = g_StratName25;
   }
   else { 
         strBuf = "MN" + IntegerToString(mag, 10);
   } 
   return strBuf;
}


bool checkExternalParam() {
   // 現在は、該当する処理無し   
   return true;
}


///
// 仮想最適化に向けた初期処理
// init()に直接記載すると煩雑になるため、関数とした。
void init_Virtual_Optimize_Env() {
   // 仮想取引の初期化
   initALL_vOrders_vOrderPLs_vOrderIndexes();

   // 前回、シフト別仮想取引発注処理を行った時間を初期化する。
   last_create_vTradeEachShift = 0;

   
   // 指定した戦略の仮想取引用パラメータを作成する。g_StratName25 = "25PIN"
   create_vOptParams_25PIN(g_StratName25);  
   string bufTime = TimeToStr(TimeLocal());
   StringReplace(bufTime, ".", "_");
   StringReplace(bufTime, ":", "_");
   string bufFileName = "init時の仮想取引用パラメータ" + bufTime + ".csv";
   write_st_25PinOptParams(bufFileName, bufTime);

   // VTRADEBACKSHIFTNUM過去シフトで仮想取引が発生すれば登録する。
   int i;
   if(SWITCH_USE_OPTIMIZER == true) {
      printf( "[%d]PB 時間測定　init()処理内で>%d<シフト前までの仮想取引開始" , __LINE__, VTRADEBACKSHIFTNUM);
      for(i = VTRADEBACKSHIFTNUM; i >= 1; i--) {
         create_vTradeEachShift_25PIN(g_StratName25,   // 戦略名。g_StratName25 = "25PIN"
                                      PinBarTimeframe, // 仮想取引の約定日を取得するための時間軸
                                      i                // どのシフトで仮想取引を試みるか
                                     );
      }

   }


   // 仮想取引の分析
   create_st_vOrderPLs(TimeCurrent());

}


// 引数で指定した戦略名に対して、用意された仮想取引用パラメータセットを使い、
// 引数で指定したシフト時点での仮想取引を行う。
// 仮想取引を発注する。
// なお、現時点では、
// ・仮想取引にはトレーディングラインを適用しない。
// ・同じ価格帯での取引禁止を適用しない。
// ・直前と同じiTime()では処理をしない
// ・v_flooringSL(FLOORING)は、関数内で実行時点のASK,BIDを使うため、過去日付（過去シフト）で使えない。
datetime last_create_vTradeEachShift = 0;
bool create_vTradeEachShift_25PIN(string mStrategy,  // 戦略名
                                  int    mTimeframe, // 仮想取引の約定日を取得するための時間軸
                                  int    mShift      // どのシフトで仮想取引を試みるか
                           ) {
   int buysellFlag = NO_SIGNAL;
   datetime vTradeTime = 0;
   string  bufStrategyComment;
   int vTradeCount = 0;
   double tpPrice = 0.0;   // 過去のシフトでv_update_AllOrdersTPSL(TP_PIPS, SL_PIPS)を使えないので、利確値を設定する。
   double slPrice = 0.0;   // 過去のシフトでv_update_AllOrdersTPSL(TP_PIPS, SL_PIPS)を使えないので、損切値を設定する。
   double openPrice = 0.0; // 過去シフトの約定日は、そのシフトの開始価格openとする。引数mShift＝で現在の時は、BIDとASKを使う

   if(last_create_vTradeEachShift > iTime(global_Symbol, mTimeframe, mShift) ) {
      printf( "[%d]PB create_vTradeEachShift中止=直前の実行時間%d=>%s<が、関数を実行しようとした時間%d=%sより将来日付のため。" , __LINE__,
              last_create_vTradeEachShift, TimeToStr(last_create_vTradeEachShift),
              iTime(global_Symbol, mTimeframe, mShift), TimeToStr(iTime(global_Symbol, mTimeframe, mShift))
            );
      return true;
   }   
   else {
      last_create_vTradeEachShift = iTime(global_Symbol, mTimeframe, mShift);
   }

      //
      // 全パラメータセットst_25PinOptParams[]を使って、シフトmShiftで仮想取引をする。
      // 
      v_trade_EachParam(mShift, st_25PinOptParams); 


      // 仮想取引で変更したトレーディングラインを戻す
      update_TradingLines(global_Symbol, 0, SHIFT_SIZE_MAXMIN);

      //
      // 決済処理。仮想取引の場合は、自動で決済することがないため、戦略の例外なく強制決済処理を実行する。
      // 
      double   mSettlePrice = iClose(global_Symbol, mTimeframe, mShift); // 注目しているシフトの終値で決済を試みる。
      datetime mSettleTime  =  iTime(global_Symbol, mTimeframe, mShift); // 決済時間した時に使う決済時間。
      if(mSettleTime > 0 && mSettlePrice > 0.0
       ) {  //強制決済用の時間と決済候補価格を取得出来たときだけ、決済処理を実施する。
         v_do_ForcedSettlement(mSettleTime, mSettlePrice, global_Symbol, TP_PIPS, SL_PIPS);

      }
   return true;
}


//
// 引数st_25PinOptParamsを使って仮想取引を行う。
//
bool v_trade_EachParam(int mShift, st_25PinOptParam &m_st_25PinOptParams[]) {
   int i;
   int buysellFlag;
   double    m_v_past_max;     // 出力：過去の最高値
   datetime  m_v_past_maxTime; // 出力：過去の最高値の時間
   double    m_v_past_min;     // 出力：過去の最安値
   datetime  m_v_past_minTime; // 出力：過去の最安値の時間
   double    m_v_past_width;   // 出力：過去値幅。past_max - past_min
   double    m_v_long_Min;     // 出力：ロング取引を許可する最小値
   double    m_v_long_Max;     // 出力：ロング取引を許可する最大値
   double    m_v_short_Min;    // 出力：ショート取引を許可する最小値
   double    m_v_short_Max;    // 出力：ショート取引を許可する最大値
   int mTimeframe = Period();
//printf( "[%d]PB シフト=%d 時間=%s で過去の仮想取引を実行する対象のパラメータセット ↓ここから" , __LINE__ , mShift, TimeToStr(Time[mShift]));
//output_st_25PinOptParams();
//printf( "[%d]PB シフト=%d 時間=%s で過去の仮想取引を実行する対象のパラメータセット　↑ここまで" , __LINE__ , mShift, TimeToStr(Time[mShift]));

      for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
         // 構造体変数st_25PinOptParams[i]のstrategyIDが空欄になれば、処理を中断する。
         if(StringLen(m_st_25PinOptParams[i].strategyID) <= 0) {

            break;
         }
         // 仮想取引を検討する戦略名。例）25PIN@@00000
         string bufStrategyComment = m_st_25PinOptParams[i].strategyID;

         // 仮想取引用にパラメータを上書きする
         overwrite_st_25PinOptParams(i);

         //
         // シフトmShift時点での売買フラグを計算する。
         //
         // 戦略別mqhの関数を呼ぶ前に、外部パラメータをグローバル変数にコピーする。
         update_GlobalParam_to_ExternalParam();
         buysellFlag = entryPinBar_Shift(mShift          // 発注判断時のシフト
                                        );

                                        
         // 仮想取引を発注する。
         // 現時点では、
         // ・仮想取引は、シフトmShiftで計算するトレーディングラインを使って、ロングの取引範囲内またはショートの取引範囲内かどうかを検証する。


         // 仮想取引は、ロングの取引範囲内またはショートの取引範囲内かどうかを検証する。
         if(buysellFlag == BUY_SIGNAL || buysellFlag == SELL_SIGNAL) {
            datetime vTradeTime = iTime(global_Symbol, mTimeframe, mShift);
            bool mflag_calc_TradingLines = false;
            mflag_calc_TradingLines = calc_TradingLines(global_Symbol,     // 通貨ペア
                                                         mTimeframe,       // 計算に使う時間軸
                                                         mShift,           // 計算対象とする先頭のシフト番号。
                                                         SHIFT_SIZE_MAXMIN,// 計算対象にするシフト数
                                                         m_v_past_max,     // 出力：過去の最高値
                                                         m_v_past_maxTime, // 出力：過去の最高値の時間
                                                         m_v_past_min,     // 出力：過去の最安値
                                                         m_v_past_minTime, // 出力：過去の最安値の時間
                                                         m_v_past_width,   // 出力：過去値幅。past_max - past_min
                                                         m_v_long_Min,     // 出力：ロング取引を許可する最小値
                                                         m_v_long_Max,     // 出力：ロング取引を許可する最大値
                                                         m_v_short_Min,    // 出力：ショート取引を許可する最小値
                                                         m_v_short_Max     // 出力：ショート取引を許可する最大値
                                                         ); 
/*printf( "[%d]PB 仮想取引のライン>>%s<< mTimeframe=%d   m_v_short_Max=%s m_v_short_Min=%s m_v_long_Max=%s m_v_long_Min=%s" , __LINE__ , TimeToStr(iTime(global_Symbol, mTimeframe, mShift)),
mTimeframe,
DoubleToStr(m_v_short_Max, global_Digits),
DoubleToStr(m_v_short_Min, global_Digits),
DoubleToStr(m_v_long_Max, global_Digits),
DoubleToStr(m_v_long_Min, global_Digits)
);*/

            if(mflag_calc_TradingLines == true){
               // シフトが０ならば、売買区分buysellFlagに応じて、BID、ASKを採用する。
               // シフトが１以上ならば、openを採用する。
               double openPrice  = get_OpenPrice(buysellFlag, mTimeframe, mShift);
/*printf( "[%d]PB 仮想取引>>%s<< openprice=%s mTimeframe=%d mShift=%d" , __LINE__ , 
TimeToStr(iTime(global_Symbol, mTimeframe, mShift)),
DoubleToStr(openPrice, global_Digits),
mTimeframe,
mShift);*/
        
               // 仮想取引の約定値openPriceが、全体範囲内に無ければエラーを返す
               if(openPrice < m_v_past_min || openPrice > m_v_past_max) {
                   printf( "[%d]PBエラー 仮想最適化用トレーディングラインの値がおかしい 約定に使おうとしている値=%s  シフト=%d 戦略＝コメント=%s 約定日=%d=%s openPrice=%s g_v_short_Min=%s g_v_short_Max=%s g_v_long_Min=%s g_v_long_Max=%s   g_v_past_max=%s g_v_past_maxTime=%s g_v_past_min=%s g_v_past_minTime=%s" , __LINE__, 
                           DoubleToStr(openPrice, global_Digits),
                           mShift,
                           bufStrategyComment,
                           vTradeTime,
                           TimeToStr(vTradeTime),
                           DoubleToStr(openPrice, global_Digits),
                           DoubleToStr(m_v_short_Min, global_Digits),
                           DoubleToStr(m_v_short_Max, global_Digits),
                           DoubleToStr(m_v_long_Min, global_Digits),
                           DoubleToStr(m_v_long_Max, global_Digits),
                           DoubleToStr(m_v_past_max, global_Digits), 
                           TimeToStr(m_v_past_maxTime),
                           DoubleToStr(m_v_past_min, global_Digits), 
                           TimeToStr(m_v_past_minTime)
                          );
               }

               // 仮想取引の約定値openPriceが、ロング範囲内に無ければ、シグナル取消
               if(buysellFlag == BUY_SIGNAL
                   && (openPrice > 0.0 && m_v_long_Min > 0.0 && m_v_long_Max > 0.0)
                   && (openPrice < m_v_long_Min || openPrice > m_v_long_Max)
                   ) {
                   buysellFlag = NO_SIGNAL;
               }
               // 仮想取引の約定値openPriceが、ショート範囲内に無ければ、シグナル取消
               else if(buysellFlag == SELL_SIGNAL
                   && (openPrice > 0.0 && m_v_short_Min > 0.0 && m_v_short_Max > 0.0)
                   && (openPrice < m_v_short_Min || openPrice > m_v_short_Max)
                   ) {
                   buysellFlag = NO_SIGNAL;
               }
               else if( (buysellFlag == BUY_SIGNAL || buysellFlag == SELL_SIGNAL) 
                        && (openPrice < m_v_past_min || openPrice > m_v_past_max)
                        ){
                   buysellFlag = NO_SIGNAL;
                   printf( "[%d]PBエラー 仮想最適化用トレーディングラインの値がおかしい シフト=%d 戦略＝コメント=%s 約定日=%d=%s openPrice=%s g_v_short_Min=%s g_v_short_Max=%s g_v_long_Min=%s g_v_long_Max=%s   g_v_past_max=%s g_v_past_maxTime=%s g_v_past_min=%s g_v_past_minTime=%s" , __LINE__, 
                           mShift,
                           bufStrategyComment,
                           vTradeTime,
                           TimeToStr(vTradeTime),
                           DoubleToStr(openPrice, global_Digits),
                           DoubleToStr(m_v_short_Min, global_Digits),
                           DoubleToStr(m_v_short_Max, global_Digits),
                           DoubleToStr(m_v_long_Min, global_Digits),
                           DoubleToStr(m_v_long_Max, global_Digits),
                           DoubleToStr(m_v_past_max, global_Digits), 
                           TimeToStr(m_v_past_maxTime),
                           DoubleToStr(m_v_past_min, global_Digits), 
                           TimeToStr(m_v_past_minTime)
                          );
               }
            }
            else {
               printf( "[%d]PBエラー シフト>%d<でトレーディングラインの計算失敗", __LINE__,mShift);
            }
         }


         int tickNo = 0;
         string externalParam = "";
         bool same_vTrade = true; // オープン中の同じ仮想取引があれば、true
         // 仮想取引のロングを発注する
         if(buysellFlag == BUY_SIGNAL) {
            if(vTradeTime <= 0) {
               vTradeTime = iTime(global_Symbol, mTimeframe, mShift);
            }
            if(openPrice <= 0.0) {
               printf( "[%d]PBエラー シフト>%d<でopenPrice=%sが取得できていない", __LINE__,mShift, DoubleToStr(openPrice, global_Digits));
               openPrice  = get_OpenPrice(buysellFlag, mTimeframe, mShift);
            }
            double tpPrice    = openPrice + NormalizeDouble(change_PiPS2Point(TP_PIPS), global_Digits*2); 
            double slPrice    = openPrice - NormalizeDouble(change_PiPS2Point(SL_PIPS), global_Digits*2); 
            // オープン中の約定日、売買、戦略名が同じ仮想取引が存在すれば、仮想取引を見送る
            same_vTrade =  
            exist_same_vTrade_OpenTimeANDBuysellANDStrat(vTradeTime,
                                                         OP_BUY,
                                                         bufStrategyComment
                                                         );
            if(same_vTrade == true) {
               // オープンしている仮想取引の中に同じ仮想取引がある。重複回避のため、仮想取引を控える。
            }
            else {
               // 損切値と利確値を引数で渡されたとおり使うv_OrderSend関数を使う
               tickNo = v_OrderSend(vTradeTime,         // 約定時刻
                                    global_Symbol,      // 通貨ペア
                                    OP_BUY,             // OP_BUY, OP_SELL
                                    LOTS,               // ロット数
                                    openPrice,          // 約定価格
                                    SLIPPAGE,           // スリップ
                                    slPrice,            // 損切値
                                    tpPrice,            // 利確値
                                    bufStrategyComment, // コメント＝戦略名。例）25PIN,00001
                                    0,                  // マジックナンバー
                                    0, 
                                    LINE_COLOR_LONG
                                 ); 
               if(tickNo > 0) {
                  get_ExternalParam_025PinBar(externalParam  // 出力：指定した戦略名で使っていた外部パラメータの^区切り文字列
                                 );
                  // 仮想取引のうち、引数のtickNoと戦略名をキーとして、仮想取引の外部パラメータを格納するexternalParamを更新する。
                  set_st_vOrder_ExternalParam(st_vOrders,
                               tickNo,             // 仮想取引st_vOrderのticket 
                               bufStrategyComment, // 仮想取引st_vOrderのstrategyID
                               externalParam       // 仮想取引st_vOrderのexternalParam
                               );                                 
               }
               else {
                  printf( "[%d]PBエラー 仮想取引（ロング）の追加失敗 OPBUY open=%s sl=%s tp=%s" , __LINE__,
                  DoubleToStr(openPrice, global_Digits),
                  DoubleToStr(slPrice, global_Digits),
                  DoubleToStr(tpPrice, global_Digits)
                  );
               }
            }  // オープン中の同じ仮想取引があるため、取引見送りの末尾
         }
         // 仮想取引のショートを発注する
         else if(buysellFlag == SELL_SIGNAL) {
            if(vTradeTime <= 0) {
               vTradeTime = iTime(global_Symbol, mTimeframe, mShift);
            }
            if(openPrice <= 0.0) {
               printf( "[%d]PBエラー シフト>%d<でopenPrice=%sが取得できていない", __LINE__,mShift, DoubleToStr(openPrice, global_Digits));
               openPrice  = get_OpenPrice(buysellFlag, mTimeframe, mShift);
            }
            tpPrice    = openPrice - NormalizeDouble(change_PiPS2Point(TP_PIPS), global_Digits*2); 
            slPrice    = openPrice + NormalizeDouble(change_PiPS2Point(SL_PIPS), global_Digits*2); 
            // オープン中の約定日、売買、戦略名、約定金額が同じ仮想取引が存在すれば、仮想取引を見送る
            same_vTrade =  
            exist_same_vTrade_OpenTimeANDBuysellANDStrat(vTradeTime,         // 約定日
                                                         OP_SELL,            // OPBUY, OP_SELL
                                                         bufStrategyComment // 戦略名
                                                         );        
            if(same_vTrade == true) {
               // オープンしている仮想取引の中に同じ仮想取引がある。重複回避のため、仮想取引を控える。
            }
            else {  
               // 損切値と利確値を引数で渡されたとおり使うv_OrderSend関数を使う
               tickNo = v_OrderSend(vTradeTime, // 約定時刻
                            global_Symbol,      // 通貨ペア
                            OP_SELL,            // OP_BUY, OP_SELL
                            LOTS,               // ロット数 
                            openPrice,          // 約定価格
                            SLIPPAGE,           // スリップ 
                            slPrice,            // 損切値
                            tpPrice,            // 利確値
                            bufStrategyComment, // コメント＝戦略名。例）25PIN,00001
                            0,                  // マジックナンバー
                            0, 
                            LINE_COLOR_SHORT); 
               if(tickNo > 0) {
                  get_ExternalParam_025PinBar(externalParam  // 出力：指定した戦略名で使っていた外部パラメータの^区切り文字列
                                          );
                  // 仮想取引のうち、引数のtickNoと戦略名をキーとして、仮想取引の外部パラメータを格納するexternalParamを更新する。
                  set_st_vOrder_ExternalParam(st_vOrders,
                                tickNo,             // 仮想取引st_vOrderのticket 
                                bufStrategyComment, // 仮想取引st_vOrderのstrategyID
                                externalParam       // 仮想取引st_vOrderのexternalParam
                                );
               }
               else {
                  printf( "[%d]PBエラー 仮想取引（ショート）の追加失敗 OPBUY open=%s sl=%s tp=%s" , __LINE__,
                  DoubleToStr(openPrice, global_Digits),
                  DoubleToStr(slPrice, global_Digits),
                  DoubleToStr(tpPrice, global_Digits)
                  );
               }                          
            } // オープン中の同じ仮想取引があるため、取引見送りの末尾
         }

         // 上書きした仮想取引用パラメータを戻す  
         recovery_st_25PinOptParams();

         // 戻した外部パラメータをグローバル変数にコピーする。
         update_GlobalParam_to_ExternalParam();
         
      } // st_25PinOptParams配列のループ末尾
      
   return true;
}

// 約定に使う約定値を取得する。
// シフトが０より大きい場合は、そのシフトのopenとする。
// シフトが０の場合は、売買区分に合わせて、BID、SDKを使う
double get_OpenPrice(int mBuySell, // 売買区分
                     int mTF,
                     int mShift    // 判定するシフト
                     ) {
   double openPrice = 0.0;                     
   if(mShift == 0) {
      if(mBuySell == BUY_SIGNAL) {
         openPrice = NormalizeDouble(MarketInfo(global_Symbol,MODE_ASK), global_Digits);
      }
      else if(mBuySell == SELL_SIGNAL) {
         openPrice = NormalizeDouble(MarketInfo(global_Symbol,MODE_BID), global_Digits);
      }
   }
   else {
      openPrice = NormalizeDouble(iOpen(global_Symbol, mTF, mShift), global_Digits);
   }
   
   return openPrice;
}


st_vOrderPL local_buf_st_vOrderPLs[VOPTPARAMSNUM_MAX];    // 【ソート用】途中経過を保存するため。戦略別・通貨ペア別・タイムフレーム別の損益集計結果
st_vOrderPL local_selected_st_vOrderPLs[VOPTPARAMSNUM_MAX];
st_vOrderPL local_selected_st_vOrderPLs1[VOPTPARAMSNUM_MAX];
st_vOrderPL local_selected_st_vOrderPLs2[VOPTPARAMSNUM_MAX];
st_vOrderPL local_selected_st_vOrderPLs3[VOPTPARAMSNUM_MAX];
st_vOrderPL local_selected_st_vOrderPLs4[VOPTPARAMSNUM_MAX];


void get_ExternalParam_025PinBar(string &mExternalParam  // 出力：指定した戦略名で使っていた外部パラメータの^区切り文字列
                                 ) {
   mExternalParam = "";
   mExternalParam = mExternalParam + "TP_PIPS=" + DoubleToStr(TP_PIPS, global_Digits) + "^";
   mExternalParam = mExternalParam + "SL_PIPS=" + DoubleToStr(SL_PIPS, global_Digits) + "^";
   mExternalParam = mExternalParam + "SL_PIPS_PER=" + DoubleToStr(SL_PIPS_PER, global_Digits) + "^";

   mExternalParam = mExternalParam + "PinBarMethod=" + IntegerToString(PinBarMethod) + "^";
   mExternalParam = mExternalParam + "PinBarTimeframe=" + IntegerToString(PinBarTimeframe) + "^";
   mExternalParam = mExternalParam + "PinBarBackstep=" + IntegerToString(PinBarBackstep) + "^";
   mExternalParam = mExternalParam + "PinBarBODY_MIN_PER=" + DoubleToStr(PinBarBODY_MIN_PER, global_Digits) + "^";
   mExternalParam = mExternalParam + "PinBarPIN_MAX_PER=" + DoubleToStr(PinBarPIN_MAX_PER, global_Digits) + "^";
}






//
// 外部パラメータにグローバル変数のパラメータセットst_25PinOptParamの識別子iの値を
// 上書きする
void overwrite_st_25PinOptParams(int i) {
   overwrite_st_25PinOptParams(st_25PinOptParams[i]);
}


//
// 外部パラメータに引数渡ししたパラメータセットm_st_25PinOptParamの値を
// 上書きする
void overwrite_st_25PinOptParams(st_25PinOptParam &m_st_25PinOptParams) {
   BUF_TP_PIPS = TP_PIPS ;                                                // 1約定あたりの利確pips数。負の時は、利確値の設定や強制利確をしない。
   TP_PIPS     = m_st_25PinOptParams.TP_PIPS;

   BUF_SL_PIPS = SL_PIPS;
   SL_PIPS         = m_st_25PinOptParams.SL_PIPS;                         // 1約定当たりの損切pips数。SL_PIPS_PER設定時は上書きされる。負の時は、損切値の設定や強制損切をしない。
   if(m_st_25PinOptParams.SL_PIPS_PER >= 0.0) {
      SL_PIPS = TP_PIPS * m_st_25PinOptParams.SL_PIPS_PER / 100.0;
   }

   BUF_SL_PIPS_PER = SL_PIPS_PER;
   SL_PIPS_PER     = m_st_25PinOptParams.SL_PIPS_PER;                     // TP_PIPSに対するSL_PPIPSの割りあい。SL_PIPSを上書きする。負の時は、上書きしない。

   BUF_FLOORING = FLOORING;
   FLOORING     = m_st_25PinOptParams.FLOORING;                           // 損切値を、オープンから指定した値(PIP)の位置に変更する。PIPS数。負の数の場合は、何もしない。            

   BUF_FLOORING_CONTINUE = FLOORING_CONTINUE;
   FLOORING_CONTINUE     = m_st_25PinOptParams.FLOORING_CONTINUE;         // trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。    

   BUF_TIME_FRAME_MAXMIN = TIME_FRAME_MAXMIN;
   TIME_FRAME_MAXMIN     = m_st_25PinOptParams.TIME_FRAME_MAXMIN;         // 1～9最高値、最安値の参照期間の単位。

   BUF_SHIFT_SIZE_MAXMIN = SHIFT_SIZE_MAXMIN;
   SHIFT_SIZE_MAXMIN     = m_st_25PinOptParams.SHIFT_SIZE_MAXMIN;         // 最高値、最安値の参照期間

   BUF_ENTRY_WIDTH_PIPS = ENTRY_WIDTH_PIPS;
   ENTRY_WIDTH_PIPS     = m_st_25PinOptParams.ENTRY_WIDTH_PIPS;           // エントリーする間隔。PIPS数。

   BUF_SHORT_ENTRY_WIDTH_PER = SHORT_ENTRY_WIDTH_PER;
   SHORT_ENTRY_WIDTH_PER     = m_st_25PinOptParams.SHORT_ENTRY_WIDTH_PER; // ショート実施帯域。過去最高値から何パーセント下までショートするか

   BUF_LONG_ENTRY_WIDTH_PER = LONG_ENTRY_WIDTH_PER; 
   LONG_ENTRY_WIDTH_PER     = m_st_25PinOptParams.LONG_ENTRY_WIDTH_PER;   // ロング実施帯域。過去最安値から何パーセント上までロングするか

//   BUF_ALLOWABLE_DIFF_PER = ALLOWABLE_DIFF_PER;
 //  ALLOWABLE_DIFF_PER     = m_st_25PinOptParams.ALLOWABLE_DIFF_PER;       // 価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値として許容するか。 

   BUF_PinBarMethod = G_PinBarMethod;
   G_PinBarMethod   = m_st_25PinOptParams.PinBarMethod;                   // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5, 110(6)=No3とNo5, 111=No1とNo3とNo5

   BUF_PinBarTimeframe = G_PinBarTimeframe;
   G_PinBarTimeframe   = m_st_25PinOptParams.PinBarTimeframe;             // ピンの計算に使う時間軸

   BUF_PinBarBackstep = G_PinBarBackstep;
   G_PinBarBackstep   = m_st_25PinOptParams.PinBarBackstep;               // 大陽線、大陰線が発生したことを何シフト前まで確認するか

   BUF_PinBarBODY_MIN_PER = G_PinBarBODY_MIN_PER;
   G_PinBarBODY_MIN_PER   = m_st_25PinOptParams.PinBarBODY_MIN_PER;       // 実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか

   BUF_PinBarPIN_MAX_PER  = G_PinBarPIN_MAX_PER;
   G_PinBarPIN_MAX_PER    = m_st_25PinOptParams.PinBarPIN_MAX_PER;        // 実体が髭のナンパ―セント以下であればピンと判断するか
}





// 第1引数m_st_vOrderPLsの中に、strategyIDが第2引数である要素があれば、trueを返す。
bool exist_st_25PinOptParam_by_StrategyID(st_vOrderPL &m_st_vOrderPLs[], // キーを持つかどうかを検索する配列
                                          string       m_selectKey       // 検索キー
                                          ) {
   int i;
   for(i = 0; i < VOPTPARAMSNUM_MAX;i++) {
      if(m_st_vOrderPLs[i].analyzeTime <= 0) {
         break;
      }
      else if( StringLen(m_st_vOrderPLs[i].strategyID) > 0 
               && StringLen(m_selectKey) > 0
               && StringCompare(m_st_vOrderPLs[i].strategyID, m_selectKey) == 0) {
         return true;
      }
   }

   return false;
}


// 指定した戦略の仮想取引用パラメータを作成する。g_StratName25 = "25PIN"
bool create_vOptParams_25PIN(string mStrategy   // 指定した戦略の仮想取引用パラメータを作成する。g_StratName25 = "25PIN"
                       ) {
   int count = 0;

   // 構造体配列st_25PinOptParams[count]の初期化
   init_st_25PinOptParams();

   //
   // st_25PinOptParams[0]は、設定されている外部パラメータの値を保持する。
   // 
   count = 0;
   st_25PinOptParams[count].strategyID            = mStrategy + "@@" + ZeroPadding(count, 5);  // g_StratNameNN + 戦略別通し番号"@@NNNNN"とする。例えば、25PIN@@00000
   st_25PinOptParams[count].TP_PIPS               = TP_PIPS;                 // 1約定あたりの利確pips数。負の時は、利確値の設定や強制利確をしない。
   st_25PinOptParams[count].SL_PIPS               = SL_PIPS;                 // 1約定当たりの損切pips数。SL_PIPS_PER設定時は上書きされる。負の時は、損切値の設定や強制損切をしない。
   st_25PinOptParams[count].SL_PIPS_PER           = SL_PIPS_PER;             // TP_PIPSに対するSL_PPIPSの割りあい。SL_PIPSを上書きする。負の時は、上書きしない。
   st_25PinOptParams[count].FLOORING              = FLOORING;                // 損切値を、オープンから指定した値(PIP)の位置に変更する。PIPS数。負の数の場合は、何もしない。            
   st_25PinOptParams[count].FLOORING_CONTINUE     = FLOORING_CONTINUE;       // trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。    
   st_25PinOptParams[count].TIME_FRAME_MAXMIN     = TIME_FRAME_MAXMIN;       // 1～9最高値、最安値を計算する時間軸。
   st_25PinOptParams[count].SHIFT_SIZE_MAXMIN     = SHIFT_SIZE_MAXMIN;       // 最高値、最安値の参照期間
   st_25PinOptParams[count].ENTRY_WIDTH_PIPS      = ENTRY_WIDTH_PIPS;        // エントリーする間隔。PIPS数。
   st_25PinOptParams[count].SHORT_ENTRY_WIDTH_PER = SHORT_ENTRY_WIDTH_PER;   // ショート実施帯域。過去最高値から何パーセント下までショートするか
   st_25PinOptParams[count].LONG_ENTRY_WIDTH_PER  = LONG_ENTRY_WIDTH_PER;    // ロング実施帯域。過去最安値から何パーセント上までロングするか
//   st_25PinOptParams[count].ALLOWABLE_DIFF_PER    = ALLOWABLE_DIFF_PER;      // 価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値として許容するか。 
   st_25PinOptParams[count].PinBarMethod          = G_PinBarMethod;          // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5, 110(6)=No3とNo5, 111=No1とNo3とNo5
   st_25PinOptParams[count].PinBarTimeframe       = G_PinBarTimeframe;       // ピンの計算に使う時間軸
   st_25PinOptParams[count].PinBarBackstep        = G_PinBarBackstep;        // 大陽線、大陰線が発生したことを何シフト前まで確認するか
   st_25PinOptParams[count].PinBarBODY_MIN_PER    = G_PinBarBODY_MIN_PER;    // 実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
   st_25PinOptParams[count].PinBarPIN_MAX_PER     = G_PinBarPIN_MAX_PER;     // 実体が髭のナンパ―セント以下であればピンと判断するか
   // デフォルト値としてコピーする。
   copy_st_25PinOptParam(st_25PinOptParams[0],    // コピー元 
                         Default_st_25PinOptParams // コピー先
                        );
   //
   // st_25PinOptParams[1]以降は、
   // 最適化結果ファイル(optResult.csv)が見つかれば、そのファイルを読み込んでパラメータセットを作る。
   // 最適化結果ファイル(optResult.csv)を使ったパラメータセット作成に失敗すれば、EA実行時に読み込んだsetファイルを使ってパラメータセットを作る
   // ※フォルダは　¥experts¥files の中のファイル以外は利用できないので注意
   // バックテストの時は、C:\Users\mclea\AppData\Roaming\MetaQuotes\Terminal\CBC2BD424D66ACE548B2A2B1EFF1A38F\tester\files
   // 【メモ】
   //    https://ameblo.jp/fxinfoblog/entry-11853347134.html 
   //    Windows 7 の場合、外部ファイルの場所がexpert\filesではない場合があるみたいです。
   //    私の場合以下でした。
   //    C:\Users\user\AppData\Roaming\MetaQuotes\Terminal\9E530F0D9ED94EDA29D4132137F69589\tester\files
   //    tester使ってテストしているためかもしれません。

   bool flag_create_vOptParams_25PIN_FromOPTResult = 
      create_vOptParams_25PIN_FromOPTResult(mStrategy, st_25PinOptParams);
   if(flag_create_vOptParams_25PIN_FromOPTResult == false) {
      // ファイルからパレメータセットを作れなかった場合は、近い値からパラメータセットを作成する。
      printf( "[%d]PB 近い値から作成したパラメータセット" , __LINE__);
      create_vOptParams_25PIN_FromSET(mStrategy, st_25PinOptParams);
   }
   else {
      printf( "[%d]PB 最適化結果ファイル(optResult.csv)から作成したパラメータセット" , __LINE__);
   }
   output_st_25PinOptParams();

   return true;
}


bool create_vOptParams_25PIN_FromSET(string mStrategy, st_25PinOptParam &m_st_25PinOptParams[]) {
   int PinBarMethod_count;
   int PinBarBODY_MIN_PER_count;
   int PinBarPIN_MAX_PER_count;

   /* 最適化パラメータ作成 888 888 */
   int count = 1;
   for(PinBarMethod_count = 1; PinBarMethod_count <= 7; PinBarMethod_count++) {                         //  7とおり
      for(PinBarBODY_MIN_PER_count = -2; PinBarBODY_MIN_PER_count <= 2; PinBarBODY_MIN_PER_count++) {   // 5とおり
         for(PinBarPIN_MAX_PER_count = -2; PinBarPIN_MAX_PER_count <= 2; PinBarPIN_MAX_PER_count++) {   // 5とおり
            m_st_25PinOptParams[count].strategyID            = mStrategy + "@@" + ZeroPadding(count, 5);       // g_StratNameNN + 戦略別通し番号"@@NNNNN"とする。例えば、25PIN@@00001
            m_st_25PinOptParams[count].TP_PIPS               = m_st_25PinOptParams[0].TP_PIPS;                 //【変動させない】1約定あたりの利確pips数。負の時は、利確値の設定や強制利確をしない。
            m_st_25PinOptParams[count].SL_PIPS_PER           = m_st_25PinOptParams[0].SL_PIPS_PER;             //【変動させない】TP_PIPSに対するSL_PPIPSの割りあい。SL_PIPSを上書きする。負の時は、上書きしない。
            m_st_25PinOptParams[count].SL_PIPS               = m_st_25PinOptParams[0].SL_PIPS;                 //【変動させない】1約定当たりの損切pips数。SL_PIPS_PER設定時は上書きされる。負の時は、損切値の設定や強制損切をしない。
            m_st_25PinOptParams[count].FLOORING              = m_st_25PinOptParams[0].FLOORING;                //【変動させない】損切値を、オープンから指定した値(PIP)の位置に変更する。PIPS数。負の数の場合は、何もしない。            
            m_st_25PinOptParams[count].FLOORING_CONTINUE     = m_st_25PinOptParams[0].FLOORING_CONTINUE;       //【変動させない】trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。    
            m_st_25PinOptParams[count].TIME_FRAME_MAXMIN     = m_st_25PinOptParams[0].TIME_FRAME_MAXMIN;       //【変動させない】1～9最高値、最安値の参照期間の単位。
            m_st_25PinOptParams[count].SHIFT_SIZE_MAXMIN     = m_st_25PinOptParams[0].SHIFT_SIZE_MAXMIN;       //【変動させない】最高値、最安値の参照期間
            m_st_25PinOptParams[count].ENTRY_WIDTH_PIPS      = m_st_25PinOptParams[0].ENTRY_WIDTH_PIPS;        //【変動させない】エントリーする間隔。PIPS数。
            m_st_25PinOptParams[count].SHORT_ENTRY_WIDTH_PER = m_st_25PinOptParams[0].SHORT_ENTRY_WIDTH_PER;   //【変動させない】ショート実施帯域。過去最高値から何パーセント下までショートするか
            m_st_25PinOptParams[count].LONG_ENTRY_WIDTH_PER  = m_st_25PinOptParams[0].LONG_ENTRY_WIDTH_PER;    //【変動させない】ロング実施帯域。過去最安値から何パーセント上までロングするか
            m_st_25PinOptParams[count].ALLOWABLE_DIFF_PER    = m_st_25PinOptParams[0].ALLOWABLE_DIFF_PER;      //【変動させない】価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値として許容するか。 
            m_st_25PinOptParams[count].PinBarMethod          = PinBarMethod_count;                             //【最適化】:1～7。001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5, 110(6)=No3とNo5, 111=No1とNo3とNo5
            m_st_25PinOptParams[count].PinBarTimeframe       = m_st_25PinOptParams[0].PinBarTimeframe;         //【変動させない】ピンの計算に使う時間軸
            m_st_25PinOptParams[count].PinBarBackstep        = m_st_25PinOptParams[0].PinBarBackstep;          //【変動させない】大陽線、大陰線が発生したことを何シフト前まで確認するか
            m_st_25PinOptParams[count].PinBarBODY_MIN_PER    = m_st_25PinOptParams[0].PinBarBODY_MIN_PER + PinBarBODY_MIN_PER_count * 10.0; // 【最適化】実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
            m_st_25PinOptParams[count].PinBarPIN_MAX_PER     = m_st_25PinOptParams[0].PinBarPIN_MAX_PER  + PinBarPIN_MAX_PER_count  * 2.5;  // 【最適化】実体が髭のナンパ―セント以下であればピンと判断するか
            // 
            // 許可できない値になる場合は、その構造体を初期化し、カウンタcountはカウントアップしない。
            // 
            if(m_st_25PinOptParams[count].PinBarBODY_MIN_PER <= 0
               || m_st_25PinOptParams[count].PinBarPIN_MAX_PER <= 0) {
               init_st_25PinOptParams(m_st_25PinOptParams[count]);
            }
            // 値に問題無ければ、カウンタcountはカウントアップ 
            else {
               count++;
            }
         }
      }
   }
   return true;
}



bool create_vOptParams_25PIN_FromOPTResult(string mStrategy,
                                           st_25PinOptParam &m_st_25PinOptParams[]) {
printf( "[%d]PB 最適化結果ファイルoptResult.csvからパラメータセットを作成する。" , __LINE__);                                           
   int i;
   string filename = "optResult.csv";
   int filehandle = FileOpen(filename,FILE_READ | FILE_TXT);
   if(filehandle < 0) {
      printf( "[%d]PB 最適化結果ファイルoptResult.csvを開けない。エラーメッセージ＝%s" , __LINE__,GetLastError());
      return false;
   }

   string sep_str[]; // 読み込んだ文字列をタブで区切った結果を格納する。
   int    sep_num;   // 読み込んだ文字列をタブで区切った結果の個数。

   int count = 1; // m_st_25PinOptParams[count=0]は外部パラメータの値が入っているため、上書き禁止。
   // ファイルが最終行に達していない間はループ
   while(FileIsEnding(filehandle) == false){
      // 1行読み込んで文字列rowに格納
      string row = FileReadString(filehandle);
      
printf( "[%d]PB 最適化結果ファイルoptResult.csvから読んだデータ=>%s<" , __LINE__, row);                                           
      
      sep_num = StringSplit(row, '\t' , sep_str);

      // m_st_25PinOptParams[0]を新しいパラメータセットの初期値として、コピーする
      copy_st_25PinOptParam(m_st_25PinOptParams[0],    // コピー元 
                            m_st_25PinOptParams[count] // コピー先
                            );
      m_st_25PinOptParams[count].strategyID = mStrategy + "@@" + ZeroPadding(count, 5);       // g_StratNameNN + 戦略別通し番号"@@NNNNN"とする。例えば、25PIN@@00001
      int pos = -1;  // キーワード（"TP_PIPS="など）が見つかった位置。先頭で見つかった時は、0
      string keyStr = "";    // キーワードを格納する変数
      string bufSubstr = ""; // キーワード以降末尾までの文字列
      int stopperNum = 0;

      // 読み込んだ1行をタブで区切った文字列の配列sep_strの各々をパラメータセットの反映する。
      int changedNum = 0; // 同じ値であってもm_st_25PinOptParams[0]から値を書き換えた項目があれば＋１する。
      for(i = 0 ; i < sep_num; i++) {
         if(i == 0) {
            m_st_25PinOptParams[count].MT4PathNo = sep_str[i];
         }
         if(i == 1) {
            m_st_25PinOptParams[count].MT4PL = sep_str[i];
         }
         if(i == 2) {
            m_st_25PinOptParams[count].MT4TradeNum = sep_str[i];
         }  
               
         keyStr = "TP_PIPS=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].TP_PIPS = NormalizeDouble(StringToDouble(bufSubstr), global_Digits);
            changedNum++;
//            continue;
         }

         keyStr = "SL_PIPS=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].SL_PIPS = NormalizeDouble(StringToDouble(bufSubstr), global_Digits);
printf( "[%d]PB 確認　SL_PIPS   %s=%s " , __LINE__, sep_str[i], DoubleToStr(m_st_25PinOptParams[count].SL_PIPS, global_Digits));                                           
            
            changedNum++;
//            continue;
         }

         keyStr = "SL_PIPS_PER=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].SL_PIPS_PER = NormalizeDouble(StringToDouble(bufSubstr), global_Digits);
            changedNum++;
 //           continue;
         }

         keyStr = "FLOORING=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].FLOORING = NormalizeDouble(StringToDouble(bufSubstr), global_Digits);
            changedNum++;
 //           continue;
         }

         keyStr = "FLOORING_CONTINUE=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].FLOORING_CONTINUE = NormalizeDouble(StringToDouble(bufSubstr), global_Digits);
            changedNum++;
 //           continue;
         }

         keyStr = "TIME_FRAME_MAXMIN=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].TIME_FRAME_MAXMIN = getTimeFrame(StringToInteger(bufSubstr));
            changedNum++;
 //           continue;
         }

         keyStr = "SHIFT_SIZE_MAXMIN=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].SHIFT_SIZE_MAXMIN = StringToInteger(bufSubstr);
            changedNum++;
 //           continue;
         }

         keyStr = "ENTRY_WIDTH_PIPS=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].ENTRY_WIDTH_PIPS = NormalizeDouble(StringToDouble(bufSubstr), global_Digits);
            changedNum++;
 //           continue;
         }

         keyStr = "SHORT_ENTRY_WIDTH_PER=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].SHORT_ENTRY_WIDTH_PER = NormalizeDouble(StringToDouble(bufSubstr), global_Digits);
            changedNum++;
 //           continue;
         }

         keyStr = "LONG_ENTRY_WIDTH_PER=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].LONG_ENTRY_WIDTH_PER = NormalizeDouble(StringToDouble(bufSubstr), global_Digits);
            changedNum++;
 //           continue;
         }

         keyStr = "ALLOWABLE_DIFF_PER=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].ALLOWABLE_DIFF_PER = NormalizeDouble(StringToDouble(bufSubstr), global_Digits);
            changedNum++;
 //           continue;
         }

         keyStr = "PinBarMethod=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].PinBarMethod = StringToInteger(bufSubstr);
            changedNum++;
  //          continue;
         }

         keyStr = "PinBarTimeframe=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].PinBarTimeframe = StringToInteger(bufSubstr);
            changedNum++;
 //           continue;
         }

         keyStr = "PinBarBackstep=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].PinBarBackstep = StringToInteger(bufSubstr);
            changedNum++;
  //          continue;
         }

         keyStr = "PinBarBODY_MIN_PER=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].PinBarBODY_MIN_PER = NormalizeDouble(StringToDouble(bufSubstr), global_Digits);
            changedNum++;
  //          continue;
         }

         keyStr = "PinBarPIN_MAX_PER=";
         pos = StringFind(sep_str[i], keyStr);
         if(pos > -1) {
            bufSubstr = StringSubstr(sep_str[i] , pos + StringLen(keyStr) , StringLen(sep_str[i]) - 1);
            m_st_25PinOptParams[count].PinBarPIN_MAX_PER = NormalizeDouble(StringToDouble(bufSubstr), global_Digits);
            changedNum++;
  //          continue;
         }

         // 配列sep_str[i]を初期化
         sep_str[i] = "";
      }
      if(changedNum == 0) {  // 読みだした行で1項目も変更しなかったため、m_st_25PinOptParams[count]を無効にし、countもカウントアップしない。
      
//         init_st_25PinOptParams(m_st_25PinOptParams[count]);
printf( "[%d]PB 最適化結果ファイルoptResult.csvからパラメータセットを作成中。count=>%d<strategyID=>%s<は、st_25PinOptParams[０]と完全一致" , __LINE__, count, m_st_25PinOptParams[count].strategyID);                                                                       

      }
      else {              // 読みだした行で1項目でも変更があれば、countをカウントアップする。
printf( "[%d]PB 確認　countアップ= %d  →　%d" , __LINE__, count, count+1);                                                                       
      
         count++;
      }

      if(count >= VOPTPARAMSNUM_MAX) {
         printf( "[%d]PB 容量オーバーのため、パラメータセットの作成を%d件で中断。" , __LINE__, VOPTPARAMSNUM_MAX);
         break;
      }

      stopperNum++;
      if(stopperNum >  VOPTPARAMSNUM_MAX + 1) {
         printf( "[%d]PBエラー 予想していない繰り返しが発生" , __LINE__);
         break;
      }
   }   // while(FileIsEnding(filehandle) == false){

   FileClose(filehandle);
   return true;
}




//
// st_25PinOptParams配列を初期化する。
//
void init_st_25PinOptParams() {
   int i;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
     
      init_st_25PinOptParams(st_25PinOptParams[i]);
   }
}

void init_st_25PinOptParams(st_25PinOptParam &m_st_25PinOptParams) {
   m_st_25PinOptParams.strategyID            = "";               // g_StratNameNN + 戦略別通し番号"@@NNNNN"とする。例えば、25PIN@@00001
   m_st_25PinOptParams.TP_PIPS               = DOUBLE_VALUE_MIN; //【最適化:5.0～100.0。+5する＝×20】1約定あたりの利確pips数。負の時は、利確値の設定や強制利確をしない。
   m_st_25PinOptParams.SL_PIPS               = DOUBLE_VALUE_MIN; //【実装保留】1約定当たりの損切pips数。SL_PIPS_PER設定時は上書きされる。負の時は、損切値の設定や強制損切をしない。
   m_st_25PinOptParams.SL_PIPS_PER           = DOUBLE_VALUE_MIN; //【最適化:10.0～30.0。+10する＝×3】TP_PIPSに対するSL_PPIPSの割りあい。SL_PIPSを上書きする。負の時は、上書きしない。
   m_st_25PinOptParams.FLOORING              = FLOORING;         //【実装保留】損切値を、オープンから指定した値(PIP)の位置に変更する。PIPS数。負の数の場合は、何もしない。            
   m_st_25PinOptParams.FLOORING_CONTINUE     = FLOORING_CONTINUE;//【実装保留】trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。    
   m_st_25PinOptParams.TIME_FRAME_MAXMIN     = INT_VALUE_MIN;    //【実装保留】1～9最高値、最安値の参照期間の単位。
   m_st_25PinOptParams.SHIFT_SIZE_MAXMIN     = INT_VALUE_MIN;    //【実装保留】最高値、最安値の参照期間
   m_st_25PinOptParams.ENTRY_WIDTH_PIPS      = DOUBLE_VALUE_MIN; //【実装保留】エントリーする間隔。PIPS数。
   m_st_25PinOptParams.SHORT_ENTRY_WIDTH_PER = DOUBLE_VALUE_MIN; //【実装保留】ショート実施帯域。過去最高値から何パーセント下までショートするか
   m_st_25PinOptParams.LONG_ENTRY_WIDTH_PER  = DOUBLE_VALUE_MIN; //【実装保留】ロング実施帯域。過去最安値から何パーセント上までロングするか
   m_st_25PinOptParams.ALLOWABLE_DIFF_PER    = DOUBLE_VALUE_MIN; //【実装保留】価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値として許容するか。 
   m_st_25PinOptParams.PinBarMethod          = INT_VALUE_MIN;    //【最適化:1～7】001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5, 110(6)=No3とNo5, 111=No1とNo3とNo5
   m_st_25PinOptParams.PinBarTimeframe       = INT_VALUE_MIN;    //【変動させない】ピンの計算に使う時間軸
   m_st_25PinOptParams.PinBarBackstep        = INT_VALUE_MIN;    //【変動させない】大陽線、大陰線が発生したことを何シフト前まで確認するか
   m_st_25PinOptParams.PinBarBODY_MIN_PER    = DOUBLE_VALUE_MIN; //【最適化:60.0～90.0。+10する＝×4】実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
   m_st_25PinOptParams.PinBarPIN_MAX_PER     = DOUBLE_VALUE_MIN; //【最適化:5.0～25.0。+5する ＝×5】実体が髭のナンパ―セント以下であればピンと判断するか
}


//
// 外部パラメーターに対してグローバル変数に上書きしたst_25PinOptParams配列の値を元に戻す。
// ※戻すのは、上書き対象であるG_PinBarMethod、G_PinBarBODY_MIN_PER、G_PinBarPIN_MAX_PERの3つのみ
void recovery_st_25PinOptParams() {
   TP_PIPS     = BUF_TP_PIPS ;
   SL_PIPS     = BUF_SL_PIPS;
   SL_PIPS_PER = BUF_SL_PIPS_PER;
   FLOORING    = BUF_FLOORING;
   FLOORING_CONTINUE     = BUF_FLOORING_CONTINUE;
   TIME_FRAME_MAXMIN     = BUF_TIME_FRAME_MAXMIN;
   SHIFT_SIZE_MAXMIN     = BUF_SHIFT_SIZE_MAXMIN;
   ENTRY_WIDTH_PIPS      = BUF_ENTRY_WIDTH_PIPS;
   SHORT_ENTRY_WIDTH_PER = BUF_SHORT_ENTRY_WIDTH_PER;
   LONG_ENTRY_WIDTH_PER  = BUF_LONG_ENTRY_WIDTH_PER; 
   //ALLOWABLE_DIFF_PER    = BUF_ALLOWABLE_DIFF_PER;
   G_PinBarMethod        = BUF_PinBarMethod;
   G_PinBarTimeframe     = BUF_PinBarTimeframe;
   G_PinBarBackstep      = BUF_PinBarBackstep;
   G_PinBarBODY_MIN_PER  = BUF_PinBarBODY_MIN_PER;
   G_PinBarPIN_MAX_PER   = BUF_PinBarPIN_MAX_PER;   

   // バッファ用グローバル変数を初期化
   BUF_PinBarMethod       = INT_VALUE_MIN;
   BUF_PinBarBODY_MIN_PER = DOUBLE_VALUE_MIN;
   BUF_PinBarPIN_MAX_PER  = DOUBLE_VALUE_MIN; 
}


//
// 設定したst_25PinOptParams配列の値を画面出力する。
//
void output_st_25PinOptParams() {
   int i;
   for(i = 0; i < VOPTPARAMSNUM_MAX;i++) {
      if(StringLen(st_25PinOptParams[i].strategyID) == 0) {
         if(i == 0) {
            printf( "[%d]VT 設定中のst_25PinOptParams[]が、1件も無い＝外部パラメータのコピーすらない" , __LINE__);
         }
         else {
            printf( "[%d]VT 設定中のst_25PinOptParams[]の登録総数は>%d<件" , __LINE__, i);
         }
         break;
      }
         string bufOutput = "";
         bufOutput = bufOutput + "戦略名:"      + st_25PinOptParams[i].strategyID;
         bufOutput = bufOutput + "TP_PIPS="     + DoubleToStr(st_25PinOptParams[i].TP_PIPS, global_Digits);
         bufOutput = bufOutput + "SL_PIPS="     + DoubleToStr(st_25PinOptParams[i].SL_PIPS, global_Digits);
         bufOutput = bufOutput + "SL_PIPS_PER=" + DoubleToStr(st_25PinOptParams[i].SL_PIPS_PER, global_Digits);
         bufOutput = bufOutput + "TIME_FRAME_MAXMIN="  + IntegerToString(st_25PinOptParams[i].TIME_FRAME_MAXMIN);
         bufOutput = bufOutput + "SHIFT_SIZE_MAXMIN="  + IntegerToString(st_25PinOptParams[i].SHIFT_SIZE_MAXMIN);
         bufOutput = bufOutput + "ENTRY_WIDTH_PIPS=" + DoubleToStr(st_25PinOptParams[i].ENTRY_WIDTH_PIPS, global_Digits);
         bufOutput = bufOutput + "SHORT_ENTRY_WIDTH_PER=" + DoubleToStr(st_25PinOptParams[i].SHORT_ENTRY_WIDTH_PER, global_Digits);
         bufOutput = bufOutput + "LONG_ENTRY_WIDTH_PER="  + DoubleToStr(st_25PinOptParams[i].LONG_ENTRY_WIDTH_PER, global_Digits);
         bufOutput = bufOutput + "ALLOWABLE_DIFF_PER="  + DoubleToStr(st_25PinOptParams[i].ALLOWABLE_DIFF_PER, global_Digits);
         bufOutput = bufOutput + "G_PinBarMethod="   + IntegerToString(st_25PinOptParams[i].PinBarMethod);
         bufOutput = bufOutput + "PinBarTimeframe="       + IntegerToString(st_25PinOptParams[i].PinBarTimeframe);
         bufOutput = bufOutput + "G_PinBarBackstep="     + IntegerToString(st_25PinOptParams[i].PinBarBackstep);
         bufOutput = bufOutput + "G_PinBarBODY_MIN_PER="     + DoubleToStr(st_25PinOptParams[i].PinBarBODY_MIN_PER, global_Digits);
         bufOutput = bufOutput + "G_PinBarPIN_MAX_PER="      + DoubleToStr(st_25PinOptParams[i].PinBarPIN_MAX_PER, global_Digits);
  
         printf( "[%d]VT st_vOrderPLs[%d] %s" , __LINE__, i, bufOutput);
   }
}

void output_st_25PinOptParams(st_25PinOptParam &m_st_25PinOptParams) {
   string bufOutput = "";

   bufOutput = bufOutput + "戦略名:>"      + m_st_25PinOptParams.strategyID + "<";
   bufOutput = bufOutput + "  TP_PIPS="     + DoubleToStr(m_st_25PinOptParams.TP_PIPS, global_Digits);
   bufOutput = bufOutput + "  SL_PIPS="     + DoubleToStr(m_st_25PinOptParams.SL_PIPS, global_Digits);
   bufOutput = bufOutput + "  SL_PIPS_PER=" + DoubleToStr(m_st_25PinOptParams.SL_PIPS_PER, global_Digits);
   bufOutput = bufOutput + "  FLOORING=" + DoubleToStr(m_st_25PinOptParams.FLOORING, global_Digits);
   bufOutput = bufOutput + "  FLOORING_CONTINUE="  + IntegerToString(m_st_25PinOptParams.FLOORING_CONTINUE);

   bufOutput = bufOutput + "  TIME_FRAME_MAXMIN="  + IntegerToString(m_st_25PinOptParams.TIME_FRAME_MAXMIN);
   bufOutput = bufOutput + "  SHIFT_SIZE_MAXMIN="  + IntegerToString(m_st_25PinOptParams.SHIFT_SIZE_MAXMIN);
   bufOutput = bufOutput + "  ENTRY_WIDTH_PIPS=" + DoubleToStr(m_st_25PinOptParams.ENTRY_WIDTH_PIPS, global_Digits);
   bufOutput = bufOutput + "  SHORT_ENTRY_WIDTH_PER=" + DoubleToStr(m_st_25PinOptParams.SHORT_ENTRY_WIDTH_PER, global_Digits);
   bufOutput = bufOutput + "  LONG_ENTRY_WIDTH_PER="  + DoubleToStr(m_st_25PinOptParams.LONG_ENTRY_WIDTH_PER, global_Digits);
   bufOutput = bufOutput + "  ALLOWABLE_DIFF_PER="  + DoubleToStr(m_st_25PinOptParams.ALLOWABLE_DIFF_PER, global_Digits);
   bufOutput = bufOutput + "  PinBarMethod="   + IntegerToString(m_st_25PinOptParams.PinBarMethod);
   bufOutput = bufOutput + "  PinBarTimeframe="       + IntegerToString(m_st_25PinOptParams.PinBarTimeframe);
   bufOutput = bufOutput + "  PinBarBackstep="     + IntegerToString(m_st_25PinOptParams.PinBarBackstep);
   bufOutput = bufOutput + "  PinBarBODY_MIN_PER="     + DoubleToStr(m_st_25PinOptParams.PinBarBODY_MIN_PER, global_Digits);
   bufOutput = bufOutput + "  PinBarPIN_MAX_PER="      + DoubleToStr(m_st_25PinOptParams.PinBarPIN_MAX_PER, global_Digits);

   printf( "[%d]PB st_vOrderPLs %s" , __LINE__, bufOutput);
}

void output_ExternalParams_25PIN() {
   string bufOutput = "";
   bufOutput = bufOutput + "戦略名:"      + "変数には持たない";
   bufOutput = bufOutput + "TP_PIPS="     + DoubleToStr(TP_PIPS, global_Digits);
   bufOutput = bufOutput + "SL_PIPS="     + DoubleToStr(SL_PIPS, global_Digits);
   bufOutput = bufOutput + "SL_PIPS_PER=" + DoubleToStr(SL_PIPS_PER, global_Digits);
   bufOutput = bufOutput + "TIME_FRAME_MAXMIN="  + IntegerToString(TIME_FRAME_MAXMIN);
   bufOutput = bufOutput + "SHIFT_SIZE_MAXMIN="  + IntegerToString(SHIFT_SIZE_MAXMIN);
   bufOutput = bufOutput + "ENTRY_WIDTH_PIPS=" + DoubleToStr(ENTRY_WIDTH_PIPS, global_Digits);
   bufOutput = bufOutput + "SHORT_ENTRY_WIDTH_PER" + DoubleToStr(SHORT_ENTRY_WIDTH_PER, global_Digits);
   bufOutput = bufOutput + "LONG_ENTRY_WIDTH_PER="  + DoubleToStr(LONG_ENTRY_WIDTH_PER, global_Digits);
//   bufOutput = bufOutput + "ALLOWABLE_DIFF_PER="  + DoubleToStr(ALLOWABLE_DIFF_PER, global_Digits);
   bufOutput = bufOutput + "G_PinBarMethod="   + IntegerToString(G_PinBarMethod);
   bufOutput = bufOutput + "PinBarTimeframe="       + IntegerToString(G_PinBarTimeframe);
   bufOutput = bufOutput + "G_PinBarBackstep="     + IntegerToString(G_PinBarBackstep);
   bufOutput = bufOutput + "G_PinBarBODY_MIN_PER="     + DoubleToStr(G_PinBarBODY_MIN_PER, global_Digits);
   bufOutput = bufOutput + "G_PinBarPIN_MAX_PER="      + DoubleToStr(G_PinBarPIN_MAX_PER, global_Digits);

   printf( "[%d]VT プログラム上の値 %s" , __LINE__, bufOutput);
}


//+------------------------------------------------------------------+
//| 仮想取引をファイル出力する。
//| 仮想取引最適化でに利用に向けて   　　　　　  |
//| ・csv形式
//| ・1行目はタイトル
//| ・先頭のデータは、^区切りで新規約定当時のパラメータ
//+------------------------------------------------------------------+
void write_vOrders_025PinBAR(string mFileName)  {
   if(VT_FILEIO_FLAG == false) {
      return ;
   }
   int i = 0;
   int fileHandle1 = FileOpen(mFileName, FILE_WRITE | FILE_CSV,",");
   string butOutput = "";
   int outputNum = 0; // 出力した仮想取引数。
   if(fileHandle1 != INVALID_HANDLE) {
      // 仮想取引が発生していなければ、その旨をファイル出力して、処理終了。
      int bufCount = 0; // 発生した仮想取引の件数。
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(st_vOrders[i].openTime <= 0) {
            break;
         }

         if(st_vOrders[i].openTime > 0) {
            bufCount++;
         }
      }
      if(bufCount == 0) {
         FileWrite(fileHandle1,
                   "仮想取引は、未発生。");
         FileClose(fileHandle1);
         return ;
      }
      // 仮想取引が発生していない場合、ここまで。

      FileWrite(fileHandle1,
                "約定時パラメータ",
                "No",
                "戦略名",
                "通貨ペア",
                "チケット番号",
                "時間軸",
                "売買",
                "約定日",
                "ロット",
                "約定値",
                "利確値",
                "損切値",
                "決済日",
                "決済値",
                "決済損益",
                "評価日",
                "評価値",
                "評価損益"
               );
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(st_vOrders[i].openTime <= 0) {
            break;
         }
         if(st_vOrders[i].openTime > 0) {
            string bufBuySell = "";
            if(st_vOrders[i].orderType == OP_BUY) {
               bufBuySell = "買い";
            }
            else if(st_vOrders[i].orderType == OP_SELL) {
               bufBuySell = "売り";
            }
            else {
               bufBuySell = IntegerToString(st_vOrders[i].orderType);
            }
            FileWrite(fileHandle1,
                      st_vOrders[i].externalParam,
                      i,
                      st_vOrders[i].strategyID,
                      st_vOrders[i].symbol,
                      st_vOrders[i].ticket,
                      st_vOrders[i].timeframe,
                      bufBuySell,
                      TimeToStr(st_vOrders[i].openTime),
                      st_vOrders[i].lots,
                      DoubleToStr(NormalizeDouble(st_vOrders[i].openPrice, global_Digits), global_Digits),
                      st_vOrders[i].orderTakeProfit,
                      st_vOrders[i].orderStopLoss,
                      TimeToStr(st_vOrders[i].closeTime),
                      DoubleToStr(NormalizeDouble(st_vOrders[i].closePrice, global_Digits), global_Digits),
                      DoubleToStr(NormalizeDouble(st_vOrders[i].closePL, global_Digits), global_Digits),
                      TimeToStr(st_vOrders[i].estimateTime),
                      DoubleToStr(NormalizeDouble(st_vOrders[i].estimatePrice, global_Digits), global_Digits),
                      DoubleToStr(NormalizeDouble(st_vOrders[i].estimatePL, global_Digits), global_Digits)
                     );
         }
      }  // for(int i = 0; i < VTRADENUM_MAX; i++) {
   }

   FileClose(fileHandle1);
}

//+------------------------------------------------------------------+
//| パラメータセットst_25PinOptParams[VOPTPARAMSNUM_MAX]をファイル出力する。
//+------------------------------------------------------------------+
void write_st_25PinOptParams(string mFileName, string mComment)  {
   int i = 0;
printf( "[%d]PB write_st_25PinOptParamsを実行。ファイル名>%s<　　コメント>%s<" , __LINE__, mFileName, mComment);   
   
   int fileHandle1 = FileOpen(mFileName, FILE_WRITE | FILE_CSV,",");
   string butOutput = "";
   int outputNum = 0; // 出力した仮想取引数。
   if(fileHandle1 != INVALID_HANDLE) {
printf( "[%d]PB st_25PinOptParamを、ファイル>%s<に出力する" , __LINE__, mFileName);   
      // 仮想取引が発生していなければ、その旨をファイル出力して、処理終了。
      int bufCount = 0; // 発生した仮想取引の件数。

      if(StringLen(mComment) > 0) {
         FileWrite(fileHandle1,
                   "コメント:",
                   mComment
                  );
      }
      FileWrite(fileHandle1,
                "strategyID",
                "TP_PIPS",
                "SL_PIPS",
                "SL_PIPS_PER",
                "FLOORING",
                "FLOORING_CONTINUE",
                "TIME_FRAME_MAXMIN",
                "SHIFT_SIZE_MAXMIN",
                "ENTRY_WIDTH_PIPS",
                "SHORT_ENTRY_WIDTH_PER",
                "LONG_ENTRY_WIDTH_PER",
                "ALLOWABLE_DIFF_PER",
                "PinBarMethod",
                "PinBarTimeframe",
                "PinBarBackstep",
                "PinBarBODY_MIN_PER",
                "PinBarPIN_MAX_PER"
               );
              
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(StringLen(st_25PinOptParams[i].strategyID) <= 0) {
            break;
         }
         string boolBuf;
         if(st_25PinOptParams[i].FLOORING_CONTINUE == true) {
            boolBuf = "true";
         }
         else if(st_25PinOptParams[i].FLOORING_CONTINUE == false) {
            boolBuf = "false";
         }
         else {
            boolBuf = "未設定";
         }

         if(StringLen(st_25PinOptParams[i].strategyID) > 0) {
            FileWrite(fileHandle1,
                      ">" + st_25PinOptParams[i].strategyID + "<",
                      DoubleToStr(st_25PinOptParams[i].TP_PIPS, global_Digits),
                      DoubleToStr(st_25PinOptParams[i].SL_PIPS, global_Digits),
                      DoubleToStr(st_25PinOptParams[i].SL_PIPS_PER, global_Digits),
                      DoubleToStr(st_25PinOptParams[i].FLOORING, global_Digits),
                      boolBuf,
                      IntegerToString(st_25PinOptParams[i].TIME_FRAME_MAXMIN),
                      IntegerToString(st_25PinOptParams[i].SHIFT_SIZE_MAXMIN),
                      DoubleToStr(st_25PinOptParams[i].ENTRY_WIDTH_PIPS, global_Digits),
                      DoubleToStr(st_25PinOptParams[i].SHORT_ENTRY_WIDTH_PER, global_Digits),
                      DoubleToStr(st_25PinOptParams[i].LONG_ENTRY_WIDTH_PER, global_Digits),
                      DoubleToStr(st_25PinOptParams[i].ALLOWABLE_DIFF_PER, global_Digits),
                      IntegerToString(st_25PinOptParams[i].PinBarMethod),
                      IntegerToString(st_25PinOptParams[i].PinBarTimeframe),
                      IntegerToString(st_25PinOptParams[i].PinBarBackstep),
                      DoubleToStr(st_25PinOptParams[i].PinBarBODY_MIN_PER, global_Digits),
                      DoubleToStr(st_25PinOptParams[i].PinBarPIN_MAX_PER, global_Digits)
                     );
         }
      }  // for(int i = 0; i < VTRADENUM_MAX; i++) {
   }

   FileClose(fileHandle1);
}

// グローバル変数st_25PinOptParams[]の中から、st_25PinOptParams[].strategyIDが引数mStrategyIDと一致する
// 配列要素を選定し、出力用引数m_selected_st_25PinOptParamにコピーする。
// 条件を満たす配列要素が見つからなければ、falseを返す。
bool select_st_25PinOptParam_by_StrategyID(string            mStrategyID,                 // 抽出条件にするst_vOrderPLs.strategyID(25PIN@@00001など）
                                           st_25PinOptParam &m_selected_st_25PinOptParam  // 出力：抽出したパラメータセット
                                           ) {
   int i;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(StringLen(st_25PinOptParams[i].strategyID) == 0) {
         break;
      }
      if(StringLen(st_25PinOptParams[i].strategyID) > 0
         && StringLen(mStrategyID) > 0
         && StringCompare(st_25PinOptParams[i].strategyID, mStrategyID) == 0) {
         m_selected_st_25PinOptParam.strategyID            = st_25PinOptParams[i].strategyID;              // g_StratNameNN + 戦略別通し番号"@@NNNNN"とする。例えば、25PIN@@00000
         m_selected_st_25PinOptParam.TP_PIPS               = st_25PinOptParams[i].TP_PIPS;                 //【最適化:5.0～100.0。+5する＝×20】1約定あたりの利確pips数。負の時は、利確値の設定や強制利確をしない。
         m_selected_st_25PinOptParam.SL_PIPS               = st_25PinOptParams[i].SL_PIPS;                 //【実装保留】1約定当たりの損切pips数。SL_PIPS_PER設定時は上書きされる。負の時は、損切値の設定や強制損切をしない。
         m_selected_st_25PinOptParam.SL_PIPS_PER           = st_25PinOptParams[i].SL_PIPS_PER;             //【最適化:10.0～30.0。+10する＝×3】TP_PIPSに対するSL_PPIPSの割りあい。SL_PIPSを上書きする。負の時は、上書きしない。
         m_selected_st_25PinOptParam.FLOORING              = st_25PinOptParams[i].FLOORING;                //【実装保留】損切値を、オープンから指定した値(PIP)の位置に変更する。PIPS数。負の数の場合は、何もしない。            
         m_selected_st_25PinOptParam.FLOORING_CONTINUE     = st_25PinOptParams[i].FLOORING_CONTINUE;       //【実装保留】trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。    
         m_selected_st_25PinOptParam.TIME_FRAME_MAXMIN     = st_25PinOptParams[i].TIME_FRAME_MAXMIN;       //【実装保留】1～9最高値、最安値の参照期間の単位。
         m_selected_st_25PinOptParam.SHIFT_SIZE_MAXMIN     = st_25PinOptParams[i].SHIFT_SIZE_MAXMIN;       //【実装保留】最高値、最安値の参照期間
         m_selected_st_25PinOptParam.ENTRY_WIDTH_PIPS      = st_25PinOptParams[i].ENTRY_WIDTH_PIPS;        //【実装保留】エントリーする間隔。PIPS数。
         m_selected_st_25PinOptParam.SHORT_ENTRY_WIDTH_PER = st_25PinOptParams[i].SHORT_ENTRY_WIDTH_PER;   //【実装保留】ショート実施帯域。過去最高値から何パーセント下までショートするか
         m_selected_st_25PinOptParam.LONG_ENTRY_WIDTH_PER  = st_25PinOptParams[i].LONG_ENTRY_WIDTH_PER;    //【実装保留】ロング実施帯域。過去最安値から何パーセント上までロングするか
         m_selected_st_25PinOptParam.ALLOWABLE_DIFF_PER    = st_25PinOptParams[i].ALLOWABLE_DIFF_PER;      //【実装保留】価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値として許容するか。 
         m_selected_st_25PinOptParam.PinBarMethod          = st_25PinOptParams[i].PinBarMethod;            //【最適化:1～7】001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5, 110(6)=No3とNo5, 111=No1とNo3とNo5
         m_selected_st_25PinOptParam.PinBarTimeframe       = st_25PinOptParams[i].PinBarTimeframe;         //【変動させない】ピンの計算に使う時間軸
         m_selected_st_25PinOptParam.PinBarBackstep        = st_25PinOptParams[i].PinBarBackstep;          //【変動させない】大陽線、大陰線が発生したことを何シフト前まで確認するか
         m_selected_st_25PinOptParam.PinBarBODY_MIN_PER    = st_25PinOptParams[i].PinBarBODY_MIN_PER;      //【最適化:60～90。+10する＝×4】実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
         m_selected_st_25PinOptParam.PinBarPIN_MAX_PER     = st_25PinOptParams[i].PinBarPIN_MAX_PER;       //【最適化:5.0～25.0。+5する ＝×5】実体が髭のナンパ―セント以下であればピンと判断するか
         return true;
      }
      else {
// printf( "[%d]PB パラメータが見つからない  mStrategyID=%s<  st_25PinOptParams[i].strategyID=>%s< 。" , __LINE__, mStrategyID,st_25PinOptParams[i].strategyID);
      }
     
   }
   return false;
}


// 最適な分析結果の戦略名（25PIN@@00001など）を持つパラメータセットを検索し、
// 出力用である第2引数にセットする。
// 関数の返り値は、選択したパラメータセットの戦略名（25PIN@@00001など
string calc_OptimizedParameterSet(st_25PinOptParam &m_selected_st_25PinOptParam)  // 出力：25PINが最適な場合のパラメータセット
 {

   // 初期化
   init_st_25PinOptParams(m_selected_st_25PinOptParam);

   // 関数get_OptimizedParameterSetNameを使って、最適な分析結果の戦略名（25PIN@@00001, 08WPR@@00001など）を取得する」、
   string optParam_StrategyName = get_OptimizedParameterSetName(g_StratName25); // 全てのパラメータセットを対象とする時は、""を渡す




   //
   // 全ての条件を満たした分析結果から取得した戦略名（25PIN@@00001, 08WPR@@00001など）が、
   // g_StratName25("25PIN")を含む時
   //   
   if(StringFind(optParam_StrategyName, g_StratName25) >= 0) {
      printf( "[%d]PB calc_OptimizedParameterSet2  optParam_StrategyName=%s がg_StratName25=>%s<を含むのでselect_st_25PinOptParam_by_StrategyID実行。" , __LINE__, 
              optParam_StrategyName,
              g_StratName25);
      bool flag_select_st_25PinOptParam_by_StrategyID = 
      select_st_25PinOptParam_by_StrategyID(optParam_StrategyName,        // 08WPR00001など
                                            m_selected_st_25PinOptParam); // 出力：抽出結果
                                            
      if(flag_select_st_25PinOptParam_by_StrategyID == true) {
         return m_selected_st_25PinOptParam.strategyID;
      }
      // 全ての条件を満たした分析結果から取得した戦略名（25PIN@@00001, 08WPR@@00001など）から、該当するパラメータセットが見つからなかった。
      else {
         printf( "[%d]PBエラー calc_OptimizedParameterSet2  get_OptimizedParameterSetNameで探した戦略名%sが見つからなかった" , __LINE__,optParam_StrategyName);
         return false;
      }
   }
   // 
   //
   // 全ての条件を満たした分析結果から取得した戦略名（25PIN@@00001, 08WPR@@00001など）が、
   // いづれにも該当しない時。
   //   
   else {
      printf( "[%d]PBエラー calc_OptimizedParameterSet2  optParam_StrategyName=%sに該当する処理が無い。" , __LINE__, optParam_StrategyName);
      return "";
   }

   return "";
}


// 全ての条件を満たす分析結果st_vOrderPLの戦略名025PIN@@00001などを返す。
// 引数mStrategyIDが対象戦略名("25PIN")を示し、""の場合は、全ての戦略を検索対象とする。
// 該当する分析結果が存在しない場合は、デフォルト値を返す
string get_OptimizedParameterSetName(string mStrategyID  // 選定するパラメータセットの戦略名を限定する。"08WPR"など
                                     ) {
   string retOptParamSetName = "";
   bool flag = get_Best_st_vOrderPL(mStrategyID, retOptParamSetName );
   // 選定できない場合は、デフォルトの戦略を設定する。

   if(flag == false || StringLen(retOptParamSetName) == 0 ) {
      printf( "[%d]PB calc_OptimizedParameterSet2  デフォルト>%s<を使用。mStrategyID=>%s<を引数にしたget_Best_st_vOrderPLがFalseか>%s<を返したため。" , __LINE__, 
               Default_st_25PinOptParams.strategyID,
               mStrategyID, retOptParamSetName);
      retOptParamSetName = Default_st_25PinOptParams.strategyID;
   }
   
   printf( "[%d]PB get_OptimizedParameterSetName の戻り値は=>%s<。" , __LINE__, retOptParamSetName);

   return retOptParamSetName;  // 出力：条件を満たしたパラメータセットの戦略名 025PIN@@00001など
}



st_vOrderPL last_Best_st_vOrderPL;
//
bool get_Best_st_vOrderPL(string  mStrategyID, // 選定する分析結果st_vOrderPLの戦略名が含む文字列。"08WPR"など
                          string &mBestParamID  // 出力：条件を満たした分析結果st_vOrderPLの戦略名 025PIN@@0001など
                                ) {
   // 初期化
   mBestParamID = "";
//printf( "[%d]PB 全量表示　ここから" , __LINE__);
//output_vOrderPLs(st_vOrderPLs);
//printf( "[%d]PB 全量表示　ここまで" , __LINE__);

   bool flag_copy_st_vOrderPL = false;
   int selectedNum = 0;
   int ii = 0;

   // 仮想取引が0件の時は、仮想最適化パラメータは計算不能
   if(st_vOrders[0].openTime <= 0) {
      printf( "[%d]PB 仮想取引が存在しないため、仮想最適化パラメータは計算不能" , __LINE__);
      return false;
   }

   // 仮想取引の分析
   create_st_vOrderPLs(TimeCurrent());

   // 分析結果を作業用の変数local_buf_st_vOrderPLsにコピーする。
   copy_st_vOrderPL(st_vOrderPLs,    // コピー元
                    local_buf_st_vOrderPLs // コピー先
                    ); 

printf( "[%d]PB get_Best_st_vOrderPL　絞り込みをする時の戦略名>%s<。" , __LINE__, mStrategyID);

   // 戦略名"25PIN"などで分析結果を絞り込む
   select_st_vOrderPLs_byStrategyID(local_buf_st_vOrderPLs,     // 抽出元
                                    mStrategyID,                // 抽出条件に使う戦略名 
                                    local_selected_st_vOrderPLs // 出力：抽出結果
   );


   // 仮想分析の結果が0件の時は、仮想最適化パラメータは計算不能
   if(StringLen(local_selected_st_vOrderPLs[0].strategyID) == 0) {
      printf( "[%d]PB 仮想取引の分析結果が存在しないため、仮想最適化パラメータは計算不能" , __LINE__);
      return false;
   }

   //
   // 1.初期設定したパラメータセットの成績を超える分析結果のみを以降の処理対象とする。
   //
   // 1.1 配列から、最小取引数OPT_MIN_TRADENUM以上の取引を持つ損益評価結果を持つデータを抽出する
   // 1.2 配列から、最大取引数(maxTradeNum0)を持つ損益評価結果を持つデータを抽出する
   // 1.3 損益の加重平均が正のデータを抽出する。加重平均は、最大５つある直近取引を(5 * 直近の損益 + 4*1つ前の損益 + 3*2つ前の損益・・・+1 *4つ前の損益) ÷　4とする。
   double winningPERLoseRate_MIN         = WINNING_PER_LOSE_RATE_MIN; // 勝ち数が負け数の何倍か・最小値。
   double winningPERLoseRate_Strategy000 = DOUBLE_VALUE_MIN;// 戦略名=08WPR@@00000の勝ち数が負け数の何倍か。
   double PF_MIN                         = PROFITFACTOR_MIN; // 抽出するパラメータセットのPFの最小値。
   double PF_Strategy000                 = DOUBLE_VALUE_MIN;// 戦略名=08WPR@@00000のPF。
   int    winNum_Strategy000  = last_Best_st_vOrderPL.win;
   int    loseNum_Strategy000 = last_Best_st_vOrderPL.lose;
   double maxPF = DOUBLE_VALUE_MIN;    // 抽出したパラメータセットのうち、プロフィットファクタの最大値
   double maxPL = DOUBLE_VALUE_MIN;    // 抽出したパラメータセットのうち、損益の最大値
   int    maxTradeNum = INT_VALUE_MIN; // 抽出したパラメータセットのうち、取引数の最大値
   
/* 20230119 取引回数が少ない時に突出して好成績が発生した場合、取引回数が増えると超えられなくなるため、各値の更新は中止。 
  // 前回選定した分析結果（=08WPR@@00000など）の勝ち倍率が、winningPERLoseRate_MINの初期値より大きければ、winningPERLoseRate_MINに上書きする。
   winningPERLoseRate_Strategy000 = calc_WinningPERLoseRate(last_Best_st_vOrderPL.win, last_Best_st_vOrderPL.lose);
   if(winningPERLoseRate_Strategy000 >= winningPERLoseRate_MIN) {
      winningPERLoseRate_MIN = NormalizeDouble(winningPERLoseRate_Strategy000, global_Digits);
   }  
   
   PF_Strategy000 = NormalizeDouble(last_Best_st_vOrderPL.ProfitFactor, global_Digits);
   // 戦略名=08WPR@@00000のPFが、PF_MINの初期値より大きければ、PF_MINに上書きする。
   if(PF_Strategy000 >= PF_MIN) {
      PF_MIN = NormalizeDouble(PF_Strategy000, global_Digits);
   }
*/    
   flag_copy_st_vOrderPL = false;
   copy_st_vOrderPL(local_selected_st_vOrderPLs,    // コピー元
                    local_buf_st_vOrderPLs // コピー先
                    );
   //
   // 分析結果local_selected_st_vOrderPLs1を独自ルールで絞り込む
   selectedNum = 0;

   selectedNum = select_st_vOrderPLs_byOriginalRules(local_buf_st_vOrderPLs,       // 抽出元
                                                     OPT_MIN_TRADENUM,             // 取引数がこの値以上のパラメータセットを抽出する。
                                                     winningPERLoseRate_MIN,       // 勝率がこの値以上のパラメータセットを抽出する。
                                                     PF_MIN,                       // プロフィットファクターがこの値以上のパラメータセットを抽出する。
                                                     local_selected_st_vOrderPLs1,  // 出力：抽出結果
                                                     maxPF,                        // 出力：抽出したパラメータセットのうち、最大のPF
                                                     maxPL,                        // 出力：抽出したパラメータセットのうち、最大の損益
                                                     maxTradeNum                   // 出力：抽出したパラメータセットのうち、最大の取引数
                                                             );


   if(selectedNum <= 0) {
      // OPT_MIN_TRADENUM以上の取引数を持つ分析結果が無ければ、、仮想最適化パラメータの計算をしない
printf( "[%d]PB 確認　select_st_vOrderPLs_byOriginalRules該当なし" , __LINE__);
      
      return false;
   }
   else {
printf( "[%d]PB 確認　select_st_vOrderPLs_byOriginalRules  maxPF=%s maxPL=%s maxTradeNum=%d" , __LINE__, 
DoubleToStr(maxPF, global_Digits),
DoubleToStr(maxPL, global_Digits),
maxTradeNum
);
   
   }

   // 2.　第1段階(初期パラメータセットの成績を超えたか？)で抽出した分析結果の最大のPFで絞り込みをする。
   if(maxPF <= PROFITFACTOR_MIN) {
      // 最大のPFがPROFITFACTOR_MIN(COMMONで定義)以下の場合は、仮想最適化パラメータの計算をしない
      printf( "[%d]PB 最大のPF=%sであり、最低限の条件PF > %sを満たす仮想取引の分析結果が存在しないため、仮想最適化パラメータは計算不能" , __LINE__,
               DoubleToStr(maxPF, global_Digits),
               DoubleToStr(PROFITFACTOR_MIN, global_Digits));
      return false;
   }
   else {
   }

   maxPF = NormalizeDouble(maxPF, global_Digits);
   selectedNum = 0;
   selectedNum = select_st_vOrderPLs_byPF(local_selected_st_vOrderPLs,   // 抽出元
                                          maxPF,                         // 抽出条件に使うプロフィットファクタ 
                                          g_Greater_Eq,                  // g_Greater_Eq=1=PF以上
                                          local_selected_st_vOrderPLs2,  // 出力：PFを使って選定した結果
                                          maxPF,                         // 出力：PFを使って選定した結果の最大PF
                                          maxPL,                         // 出力：PFを使って選定した結果の最大損益
                                          maxTradeNum                    // 出力：PFを使って選定した結果の最大取引数
                                          ); // 出力：抽出結果

   if(selectedNum <= 0) {
      return false;
   }

   // 3.　第2段階(最大のPFを持つモノ)で抽出した分析結果の最大の損益で絞り込みをする。
   if(maxPL <= 0.0) {  // 出力：PFを使って選定した結果の最大損益
      // 最大の損益が0.0以下の場合は、仮想最適化パラメータの計算をしない
      printf( "[%d]PB 最低限の条件、損益>=0.0を満たす仮想取引の分析結果が存在しないため、仮想最適化パラメータは計算不能" , __LINE__);
      return false;
   }
   maxPL = NormalizeDouble(maxPL, global_Digits);
   selectedNum = 0;
   selectedNum = select_st_vOrderPLs_byPL(local_selected_st_vOrderPLs2,  // 抽出元   
                                          maxPL,                         // 抽出条件に使う損益
                                          g_Greater_Eq,                  // g_Greater_Eq=1=損益以上
                                          local_selected_st_vOrderPLs3,  // 出力：損益を使って抽出結果
                                          maxPF,                         // 出力：損益を使って選定した結果の最大PF
                                          maxPL,                         // 出力：損益を使って選定した結果の最大損益
                                          maxTradeNum                    // 出力：損益を使って選定した結果の最大取引数
                                          ); // 出力：抽出結果                                          
   if(selectedNum <= 0) {
      printf( "[%d]PB 損益>=%sを満たす仮想取引の分析結果が存在しないため、仮想最適化パラメータは計算不能" , __LINE__, 
                 DoubleToStr(maxPL, global_Digits));
      return false;
   }
   // 最大PL(maxPL)を持つ仮想取引の分析結果が1件しかなければ、以降の抽出不要。仮想最適化パラメータが確定。

   // 4.　第3段階(最大の損益を持つモノ)で抽出した分析結果の最大の取引数で絞り込みをする。
   if(maxTradeNum <= 0) {
      // 最大の取引数が0以下の場合は、仮想最適化パラメータの計算をしない
      printf( "[%d]PB 最低限の条件取引数>=0を満たす仮想取引の分析結果が存在しないため、仮想最適化パラメータは計算不能" , __LINE__);
      return false;
   }

   selectedNum = 0;
   selectedNum = select_st_vOrderPLs_byTradeNum(local_selected_st_vOrderPLs3,    // 抽出元
                                                maxTradeNum,            // 抽出条件に使う取引件数
                                                g_Greater_Eq,           // g_Greater_Eq=1=取引件数以上
                                                local_selected_st_vOrderPLs4); // 出力：抽出結果

printf( "[%d]PB 全ての条件を満たす分析結果>%d<件のうち、結果トップ10" , __LINE__, selectedNum);
for(ii = 0; ii < 10; ii++) {
   if(local_selected_st_vOrderPLs4[ii].analyzeTime <= 0) {
      break;
   }
   output_vOrderPLs(local_selected_st_vOrderPLs4[ii]);
}
printf( "[%d]PB 全ての条件を満たす分析結果のうち、結果トップ10ーーー終了" , __LINE__, maxTradeNum);


   // 5.　第4段階(最大の取引数を持つモノ)で抽出したパラメータセット別分析結果の最大の取引数で絞り込みをする。
   if(selectedNum <= 0) {
      return false;
   }
   // 条件を満たす分析結果が1件しかなければ、以降の抽出不要。仮想最適化パラメータが確定。
   else if(selectedNum == 1) {
      mBestParamID = local_selected_st_vOrderPLs4[0].strategyID;
printf( "[%d]PB get_Best_st_vOrderPL　条件を満たす分析結果が1つのため、>%s<を選定。" , __LINE__, mBestParamID);

      // last_Best_st_vOrderPLに選択した分析結果をコピーする。
      copy_st_vOrderPL(local_selected_st_vOrderPLs4[0],    // コピー元
                       last_Best_st_vOrderPL               // コピー先
                       );
      return true;
   }

   // 条件を満たす分析結果が複数ある場合は、取引数が最大のものを優先する。
   else if(selectedNum > 1) {
      mBestParamID = local_selected_st_vOrderPLs4[0].strategyID;  
      printf( "[%d]PB 最終条件を満たす分析結果が>%d<あったため、1件目>%s<を選択" , __LINE__, selectedNum, mBestParamID);

      // last_Best_st_vOrderPLに選択した分析結果をコピーする。
      copy_st_vOrderPL(local_selected_st_vOrderPLs4[0],    // コピー元
                       last_Best_st_vOrderPL               // コピー先
                    );

      return true;
   }
   else {
      printf( "[%d]PBエラー　想定外のケースが発生したため、get_Best_st_vOrderPLを異常終了した。" , __LINE__);
      return false;
   }

   return false;
}






