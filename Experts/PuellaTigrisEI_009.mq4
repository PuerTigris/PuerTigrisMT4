 // 20230502 新方式で作り直し。
// ・シグナル検討のための、戦略別のパラメータを読み込む
// 　利用する戦略は、バックテストで過去1年分の最適化でPFが1.2以上のパラメータを使う。
// ・7つのテクニカルで売買シグナルを計算。
// ・シグナル発生から経過したシフト数をiBarShiftで計算して持ち点とする。発生直後 = 0点。1シフト後 = 1点。
// ・20点を超えるか逆方向のシグナルが発生したら、持ち点は最悪値9999にする。
// ・各戦略のシグナルが同じかNO_SIGNALで、売買シグナルが出ている戦略の持ち点の合計が、指定値以下だったら、発注する。　


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
#include <Tigris_TradingLine.mqh>

#include <Puer_TBB.mqh> 
#include <Puer_SAR.mqh>
#include <Puer_MRA.mqh>
#include <Puer_PinBAR.mqh>
#include <Puer_WPR.mqh>
#include <Puer_CORR.mqh>	 
#include <Puer_KAGI.mqh>
#include <Puer_Ichimoku.mqh>
//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
input int    MagicNumberTrendEI   = 90000020;
input int    G_SIGNAL_LIFE        = 20;   // 単位はmsec。 売買フラグ設定後、この設定値の時間msecを超えたら売買フラグをリセットする。
input double G_TRADE_BORDER       = 1000; // 単位はmsec。 売買フラグのポイント合計がこの値未満の時に売買シグナルを発生させる。
input int    G_MAX_OPEN_TRADENUM  = 2;    // 同時にオープンな状態の取引がいくつまで許すか。
input bool   TRADE_PLUS_SWAP      = true; // 

//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
string PGName = "PuerTigris";             //プログラム名				
int    MAX_STRATEGIES = 100;

//足1本で1回の処理をするための変数
datetime CONTROLALLtime0 = 0;

//EAが大量のオーダーを重複して出力するのを避けるための変数。
datetime TrendBBTime0 = 0;     

struct st_Strategy {
   string   strategy;      // 戦略。TB, SR, MRA, PB, WP, CR, KG。
   int      buysellSignal; // 売買シグナル。BUY_SIGNAL, SELL_SIGNAL, NO_SIGNAL
   datetime signalTime;    // シグナルが発生した時刻。NO_SIGNAL時は-1
   int      point;         // 持ち点。シグナル数又は最悪値。初期値は、最悪値9999
   datetime lastCheckTime; // 直近の判定時刻
};
st_Strategy st_Strategies[100];

double BUF_TP_PIPS;
double BUF_SL_PIPS;
double BUF_FLOORING;
bool   BUF_FLOORING_CONTINUE;
double BUF_SHORT_ENTRY_WIDTH_PER;
double BUF_LONG_ENTRY_WIDTH_PER;


// 777
// TBB用グローバル変数
double mTP_PIPS_TB  = 5.0;
double mSL_PIPS_TB  = 85.0;
double mFlooring_TB = -5.0;
bool   mFlooring_continue_TB    = false;
double mShort_Entry_With_PER_TB = 100.0;
double mLong_Entry_With_PER_TB  = 100.0;
double g_TBBSigma = 5.0;
int    g_TBTimeframe = 0;


// SAR用グローバル変数
double mTP_PIPS_SR  = 105.0;
double mSL_PIPS_SR  = 105.0;
double mFlooring_SR = -5.0;
bool   mFlooring_continue_SR    = false;
double mShort_Entry_With_PER_SR = 100.0;
double mLong_Entry_With_PER_SR  = 100.0;
double g_SAR_ADX = 20.0;


// MRA用グローバル変数
double mTP_PIPS_MRA  = 105.0;
double mSL_PIPS_MRA  = 105.0;
double mFlooring_MRA = -5.0;
bool   mFlooring_continue_MRA    = false;
double mShort_Entry_With_PER_MRA = 100.0;
double mLong_Entry_With_PER_MRA  = 100.0;
int    g_MRA_DEGREE   = 9;     // 重回帰分析をする際の次数。次数は2以上にすること
int    g_MRA_EXP_TYPE = 1;     // 重回帰分析をする際の説明変数データ群のデータパターン。1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, slopeH4、2:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, rsi
int    g_MRA_DATA_NUM = 100;   // 重回帰分析をする際のデータ件数。次数＋２以上にすること
double g_MRA_TP_PIPS  = 105.0; // 利益がこの値を超えそうであれば、シグナルを発する。
double g_MRA_SL_PIPS  = 105.0; // 利益がこの値を超えそうであれば、シグナルを解消する。


// PB用グローバル変数
double mTP_PIPS_PB  = 105.0;
double mSL_PIPS_PB  = 105.0;
double mFlooring_PB = -5.0;
bool   mFlooring_continue_PB    = false;
double mShort_Entry_With_PER_PB = 100.0;
double mLong_Entry_With_PER_PB  = 100.0;
int    g_PinBarMethod       = 1;    // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5, 110(6)=No3とNo5, 111=No1とNo3とNo5  
int    g_PinBarTimeframe    = 0;    // ピンの計算に使う時間軸
int    g_PinBarBackstep     = 10;   // 大陽線、大陰線が発生したことを何シフト前まで確認するか
double g_PinBarBODY_MIN_PER = 60.0; // 実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
double g_PinBarPIN_MAX_PER  = 10.0; // 実体が髭のナンパ―セント以下であればピンと判断するか

// WPR用グローバル変数
double mTP_PIPS_WPR  = 105.0;
double mSL_PIPS_WPR  = 105.0;
double mFlooring_WPR = -5.0;
bool   mFlooring_continue_WPR    = false;
double mShort_Entry_With_PER_WPR = 100.0;
double mLong_Entry_With_PER_WPR  = 100.0;
double g_WPRLow         = -60;  //ウィリアムズWPRのLow
double g_WPRHigh        = -40;  //ウィリアムズWPRのHigh	「-20%を超えれば買われ過ぎで「売りサイン」
int    g_WPRgarbage     = 100;  //過去WPRgarbage個のWPRのうち、WPRgarbageRate％の割合でWPRLowを下回っている個数があれば売りとみなす（ガーベージボトム）
double g_WPRgarbageRate = 20.0;


// CORREL用グローバル変数
double mTP_PIPS_CR  = 105.0;
double mSL_PIPS_CR  = 105.0;
double mFlooring_CR = -5.0;
bool   mFlooring_continue_CR    = false;
double mShort_Entry_With_PER_CR = 100.0;
double mLong_Entry_With_PER_CR  = 100.0;
int    g_CORREL_TF_SHORTER = 1;    //0から9。2は、PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
int    g_CORREL_TF_LONGER  = 5;    //0から9。PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
double g_CORRELLower       = -0.225; //-1.0～+1.0。2つのタイムフレーム間の相関係数のため、絶対値は1未満。
double g_CORRELHigher      = 0.225;  //-1.0～+1.0。2つのタイムフレーム間の相関係数のため、絶対値は1未満。
int    g_CORREL_period     = 200;

// KAGI用グローバル変数
double mTP_PIPS_KG  = 105.0;
double mSL_PIPS_KG  = 105.0;
double mFlooring_KG = -5.0;
bool   mFlooring_continue_KG    = false;
double mShort_Entry_With_PER_KG = 100.0;
double mLong_Entry_With_PER_KG  = 100.0;
double g_KAGIPips   = 20;  // このPIPS数を超えた上下があった場合に、カギを更新する。
int    g_KAGISize    = 40; // 何本前のシフトからカギの計算をするか。
int    g_KAGIMethod  = 1;  // 1:一段抜きで売買、2:三尊で売買、3:五瞼で売買

// Ichimoku用グローバル変数
double mTP_PIPS_IM  = 105.0;
double mSL_PIPS_IM  = 105.0;
double mFlooring_IM = -5.0;
bool   mFlooring_continue_IM    = false;
double mShort_Entry_With_PER_IM = 100.0;
double mLong_Entry_With_PER_IM  = 100.0;
int    g_ICHIMOKU_SPANTYPE = 0; // 0の時、転換線期間=9、基準線期間=26、先行スパン期間=52
                                // 1の時、転換線期間=7、基準線期間=21、先行スパン期間=42
int    g_ICHIMOKU_METHOD = 3;   //1～5
                                // １．基準線と転換線のクロス　＝ ICHIMOKU_METHOD = 1
                                // ２．遅行スパンと価格のクロス＝ ICHIMOKU_METHOD = 2。ただし、上記１も満たすこと。
                                // ３．雲のブレイクアウト　　　＝ ICHIMOKU_METHOD = 3。ただし、上記１、２も満たすこと。
                                // ４．基準線と価格のクロス　　＝ ICHIMOKU_METHOD = 4。ただし、上記１～３も満たすこと。
                                // ５．雲のねじれ　　　　　　　＝ ICHIMOKU_METHOD = 5。ただし、上記１～４も満たすこと。


int    g_MAX_OPEN_TRADENUM = 999;    // 同時にオープンな状態の取引がいくつまで許すか。

//+------------------------------------------------------------------+	
//| 初期処理                                                         |	
//+------------------------------------------------------------------+	
int init()	
{	
   //オブジェクトの削除	
   MyObjectsDeleteAll();

   updateExternalParamCOMM();
   updateExternalParam_TradingLine();

   // 初期状態の外部パラメータをグローバル変数にコピーする。
   update_GlobalParam_to_ExternalParam();
   
   // st_Strategyの初期化
   init_st_Strategy();
   
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
   ENUM_TIMEFRAMES TIME_FRAME_MAXMIN_ENUM = changeInt2ENUMTIMEFRAME(TIME_FRAME_MAXMIN);
   bool flag_calc_TradingLines = calc_TradingLines(global_Symbol, 
                                                   TIME_FRAME_MAXMIN_ENUM, 
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
   return(INIT_SUCCEEDED);	
}	
	
//+------------------------------------------------------------------+	
//| 終了処理                                                         |	
//+------------------------------------------------------------------+	
int deinit() {	
output_st_Strategies();
output_st_TradeHistories();
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
   ENUM_TIMEFRAMES TIME_FRAME_MAXMIN_ENUM = changeInt2ENUMTIMEFRAME(TIME_FRAME_MAXMIN);
   ShowTestMsg = false;

   //
   // トレーディングラインの更新
   //
   // BIDが過去最大値を超えた場合は、トレンドが大きく変わったと判断して、トレーディングラインを見直し
   tmpBID = NormalizeDouble(Bid, global_Digits);
   if(g_past_max > 0.0 
      && NormalizeDouble(g_past_max, global_Digits) < NormalizeDouble(tmpBID, global_Digits)) {  
      update_TradingLines(global_Symbol, 
                          TIME_FRAME_MAXMIN_ENUM, 
                          SHIFT_SIZE_MAXMIN);
   }

   // ASKが過去最小値を下回った場合は、トレンドが大きく変わったと判断して、トレーディングラインを見直し
   tmpASK = NormalizeDouble(Ask, global_Digits);
   if(g_past_min > 0.0 
      && NormalizeDouble(g_past_min, global_Digits) > NormalizeDouble(tmpASK, global_Digits)) {  
      update_TradingLines(global_Symbol, 
                          TIME_FRAME_MAXMIN_ENUM, 
                          SHIFT_SIZE_MAXMIN);        
   }

   if(TrendBBTime0 != Time[0]) {
      int openTradeNum = -1;
     
      openTradeNum = get_OpenTradeNum(MagicNumberTrendEI);
      if(openTradeNum < G_MAX_OPEN_TRADENUM) {   
         
         entryByStrategies(MagicNumberTrendEI);
      }
      else {
         printf( "[%d] 同時オープン可能な%d件をオーバーするため、実取引の検討せず。" , __LINE__ , G_MAX_OPEN_TRADENUM);
      }      
   }
   


   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、全オーダーの指値と逆指値をセットする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      update_AllOrdersTPSL(global_Symbol, MagicNumberTrendEI, TP_PIPS, SL_PIPS);
   } 

   //最小利食値FLOORINGが設定されていれば、損切値の更新を試す。
   if(FLOORING >= 0) {
      flooringSL(global_Symbol, MagicNumberTrendEI, FLOORING, FLOORING_CONTINUE);
   }

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、マジックナンバーをキーとして強制決済をする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      do_ForcedSettlement(MagicNumberTrendEI, global_Symbol, TP_PIPS, SL_PIPS);
   } 
  
   return(0);	
}	
	


//
// 外部パラメータをグローバル変数にコピーする。
//
void update_GlobalParam_to_ExternalParam() {
}

// 
//+------------------------------------------------------------------+
//| entryByStrategies(MagicNumberTrendEI)   PuerTigris026.mq4から抜粋               　      |
//+------------------------------------------------------------------+ 
// ・毎時、各戦略で売買シグナルを計算する。
// ・計算した売買シグナル、時刻を更新する。
// ・シグナルが発生した時刻が何シフト前かと持ち点を更新する。
// ・NO_SIGNALを除いて、
//  - 全戦略の売買シグナルが同じ（売り又は買い）
// 　- 2つ以上の戦略が同じ（売り又は買い）
// 　- 持ち点合計が規定値未満
// 　であれば、売買シグナルを確定する。 
bool entryByStrategies(int mMagic) {
   update_st_Strategy_ShiftPoint();
   update_st_TradeHistories();

   int buysellSignal = NO_SIGNAL;

   // 戦略別mqhの関数を使用する。
   // TBBの場合
   overwrite_ExternalParams(mTP_PIPS_TB,             //double mTP_PIPS,
                            mSL_PIPS_TB,             //  double mSL_PIPS,
                            mFlooring_TB,            //  double mFlooring,
                            mFlooring_continue_TB,   //  bool   mFlooring_continue,
                            mShort_Entry_With_PER_TB,//  double mShort_Entry_With_PER,
                            mLong_Entry_With_PER_TB  //  double mLong_Entry_With_PER
                              );
   TBBSigma    = g_TBBSigma;
   TBTimeframe = g_TBTimeframe;                              
   buysellSignal = entryTrendBB();
   update_st_Strategy("TB",
                     buysellSignal,
                     iTime(Symbol(), PERIOD_CURRENT, 0)
                     );
   recovery_ExternalParams();

   // SARの場合
   overwrite_ExternalParams(mTP_PIPS_SR,             //double mTP_PIPS,
                            mSL_PIPS_SR,             //  double mSL_PIPS,
                            mFlooring_SR,            //  double mFlooring,
                            mFlooring_continue_SR,   //  bool   mFlooring_continue,
                            mShort_Entry_With_PER_SR,//  double mShort_Entry_With_PER,
                            mLong_Entry_With_PER_SR  //  double mLong_Entry_With_PER
                              );
   SAR_ADX = g_SAR_ADX;
                              
   buysellSignal = entrySAR();
   update_st_Strategy("SR",
                     buysellSignal,
                     iTime(Symbol(), PERIOD_CURRENT, 0)
                     );
   recovery_ExternalParams();

   // MRAの場合
   overwrite_ExternalParams(mTP_PIPS_MRA,             //double mTP_PIPS,
                            mSL_PIPS_MRA,             //  double mSL_PIPS,
                            mFlooring_MRA,            //  double mFlooring,
                            mFlooring_continue_MRA,   //  bool   mFlooring_continue,
                            mShort_Entry_With_PER_MRA,//  double mShort_Entry_With_PER,
                            mLong_Entry_With_PER_MRA  //  double mLong_Entry_With_PER
                              );
   MRA_DEGREE   = g_MRA_DEGREE;   // 重回帰分析をする際の次数。次数は2以上にすること
   MRA_EXP_TYPE = g_MRA_EXP_TYPE; // 重回帰分析をする際の説明変数データ群のデータパターン。1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, slopeH4、2:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, rsi
   MRA_DATA_NUM = g_MRA_DATA_NUM; // 重回帰分析をする際のデータ件数。次数＋２以上にすること
   MRA_TP_PIPS  = g_MRA_TP_PIPS;  // 利益がこの値を超えそうであれば、シグナルを発する。
   MRA_SL_PIPS  = g_MRA_SL_PIPS;  // 利益がこの値を超えそうであれば、シグナルを解消する。

   buysellSignal = entryMRA();
   update_st_Strategy("MRA",
                     buysellSignal,
                     iTime(Symbol(), PERIOD_CURRENT, 0)
                     );
   recovery_ExternalParams();

   // PBの場合
   overwrite_ExternalParams(mTP_PIPS_PB,             //double mTP_PIPS,
                            mSL_PIPS_PB,             //  double mSL_PIPS,
                            mFlooring_PB,            //  double mFlooring,
                            mFlooring_continue_PB,   //  bool   mFlooring_continue,
                            mShort_Entry_With_PER_PB,//  double mShort_Entry_With_PER,
                            mLong_Entry_With_PER_PB  //  double mLong_Entry_With_PER
                              );
   PinBarMethod       = g_PinBarMethod;       // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5, 110(6)=No3とNo5, 111=No1とNo3とNo5  
   PinBarTimeframe    = g_PinBarTimeframe;    // ピンの計算に使う時間軸
   PinBarBackstep     = g_PinBarBackstep;     // 大陽線、大陰線が発生したことを何シフト前まで確認するか
   PinBarBODY_MIN_PER = g_PinBarBODY_MIN_PER; // 実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
   PinBarPIN_MAX_PER  = g_PinBarPIN_MAX_PER;  // 実体が髭のナンパ―セント以下であればピンと判断するか

   buysellSignal = entryPinBar();
   update_st_Strategy("PB",
                     buysellSignal,
                     iTime(Symbol(), PERIOD_CURRENT, 0)
                     );
   recovery_ExternalParams();

   // WPRの場合
   overwrite_ExternalParams(mTP_PIPS_WPR,             //double mTP_PIPS,
                            mSL_PIPS_WPR,             //  double mSL_PIPS,
                            mFlooring_WPR,            //  double mFlooring,
                            mFlooring_continue_WPR,   //  bool   mFlooring_continue,
                            mShort_Entry_With_PER_WPR,//  double mShort_Entry_With_PER,
                            mLong_Entry_With_PER_WPR  //  double mLong_Entry_With_PER
                              );
   WPRLow         = g_WPRLow;      	//ウィリアムズWPRのLow						
   WPRHigh        = g_WPRHigh;   	//ウィリアムズWPRのHigh	「-20%を超えれば買われ過ぎで「売りサイン」
   WPRgarbage     = g_WPRgarbage;   //過去WPRgarbage個のWPRのうち、WPRgarbageRate％の割合でWPRLowを下回っている個数があれば売りとみなす（ガーベージボトム）
   WPRgarbageRate = g_WPRgarbageRate;

   buysellSignal = entryRangeWPR();
   update_st_Strategy("WP",
                     buysellSignal,
                     iTime(Symbol(), PERIOD_CURRENT, 0)
                     );
   recovery_ExternalParams();

   // CORRELの場合
   overwrite_ExternalParams(mTP_PIPS_CR,             //double mTP_PIPS,
                            mSL_PIPS_CR,             //  double mSL_PIPS,
                            mFlooring_CR,            //  double mFlooring,
                            mFlooring_continue_CR,   //  bool   mFlooring_continue,
                            mShort_Entry_With_PER_CR,//  double mShort_Entry_With_PER,
                            mLong_Entry_With_PER_CR  //  double mLong_Entry_With_PER
                              );
   CORREL_TF_SHORTER = g_CORREL_TF_SHORTER; //0から9。2は、PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
   CORREL_TF_LONGER  = g_CORREL_TF_LONGER;  //0から9。PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
   CORRELLower       = g_CORRELLower;       //-1.0～+1.0。2つのタイムフレーム間の相関係数のため、絶対値は1未満。
   CORRELHigher      = g_CORRELHigher;      //-1.0～+1.0。2つのタイムフレーム間の相関係数のため、絶対値は1未満。
   CORREL_period     = g_CORREL_period;

   buysellSignal = orderByCORREL_TIME();
   update_st_Strategy("CR",
                     buysellSignal,
                     iTime(Symbol(), PERIOD_CURRENT, 0)
                     );
   recovery_ExternalParams();

   // KAGIの場合
   overwrite_ExternalParams(mTP_PIPS_KG,             //double mTP_PIPS,
                            mSL_PIPS_KG,             //  double mSL_PIPS,
                            mFlooring_KG,            //  double mFlooring,
                            mFlooring_continue_KG,   //  bool   mFlooring_continue,
                            mShort_Entry_With_PER_KG,//  double mShort_Entry_With_PER,
                            mLong_Entry_With_PER_KG  //  double mLong_Entry_With_PER
                              );
   KAGIPips   = g_KAGIPips;
   KAGISize   = g_KAGISize;
   KAGIMethod = g_KAGIMethod;  
                    
   buysellSignal = entryKAGI();
   update_st_Strategy("KG",
                     buysellSignal,
                     iTime(Symbol(), PERIOD_CURRENT, 0)
                     );
   recovery_ExternalParams();

   // Ichimokuの場合
   overwrite_ExternalParams(mTP_PIPS_IM,             //double mTP_PIPS,
                            mSL_PIPS_IM,             //  double mSL_PIPS,
                            mFlooring_IM,            //  double mFlooring,
                            mFlooring_continue_IM,   //  bool   mFlooring_continue,
                            mShort_Entry_With_PER_IM,//  double mShort_Entry_With_PER,
                            mLong_Entry_With_PER_IM  //  double mLong_Entry_With_PER
                              );
   ICHIMOKU_SPANTYPE = g_ICHIMOKU_SPANTYPE; // 0の時、転換線期間=9、基準線期間=26、先行スパン期間=52
                                          // 1の時、転換線期間=7、基準線期間=21、先行スパン期間=42
   ICHIMOKU_METHOD   = g_ICHIMOKU_METHOD;  //1～5

                              
   buysellSignal = entryIchimokuMACD();
   update_st_Strategy("IM",
                     buysellSignal,
                     iTime(Symbol(), PERIOD_CURRENT, 0)
                     );
   recovery_ExternalParams();      
   
   buysellSignal = get_Signal_from_st_Strategy();

   int ticket_num = 0;
   int intTrend = NoTrend;
   bool mFlag = false;
   double sl = 0.0;
   double tp = 0.0;

   
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
   ENUM_TIMEFRAMES TIME_FRAME_MAXMIN_ENUM = changeInt2ENUMTIMEFRAME(TIME_FRAME_MAXMIN);
   
   if(buysellSignal == BUY_SIGNAL || buysellSignal == SELL_SIGNAL) {
      update_TradingLines(global_Symbol, 
                          TIME_FRAME_MAXMIN_ENUM, 
                          SHIFT_SIZE_MAXMIN);
   
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
   }
   double mMarketinfoMODE_ASK;
   double mMarketinfoMODE_BID;

   // 4時間足の傾きでシグナルを見直す。
   if(buysellSignal == BUY_SIGNAL || buysellSignal == SELL_SIGNAL) {
      int trend = get_Trend_EMA_PERIODH4(global_Symbol, 0);
      if(buysellSignal == BUY_SIGNAL && trend == DownTrend) {
printf( "[%d]EI 4時間足でシグナル消滅" , __LINE__);
         buysellSignal = NO_SIGNAL;
      }
      else if(buysellSignal == SELL_SIGNAL && trend == UpTrend) {
printf( "[%d]EI 4時間足でシグナル消滅" , __LINE__);      
         buysellSignal = NO_SIGNAL;         
      }
   }
      
   // トレーディングラインを使って、発注予定値が条件を満たすかどうかを判断する。
   // 発注不可の値であれば、シグナルをNO_SIGNALに変更する。
   bool flag_is_TradablePrice;
   if( buysellSignal == BUY_SIGNAL) {
      mMarketinfoMODE_ASK = MarketInfo(global_Symbol,MODE_ASK);   
      flag_is_TradablePrice = 
         is_TradablePrice(mMagic,
                          BUY_SIGNAL,
                          long_Max,
                          long_Min,
                          ENTRY_WIDTH_PIPS,     // 何PIPSの間隔をあけるか
                          mMarketinfoMODE_ASK); // 発注予定値
      if(flag_is_TradablePrice == false) {
printf( "[%d]EI トレーディングラインでシグナル消滅　現在=%s ロング最大=%s 　最小=%s" , __LINE__,
         DoubleToString(mMarketinfoMODE_ASK, 5), DoubleToString(long_Max, 5), DoubleToString(long_Min, 5));            
         buysellSignal = NO_SIGNAL;
      }
   }
   else if( buysellSignal == SELL_SIGNAL) {
      mMarketinfoMODE_BID = MarketInfo(global_Symbol,MODE_BID);
      flag_is_TradablePrice = 
         is_TradablePrice(mMagic,
                          SELL_SIGNAL,
                          short_Max,
                          short_Min,
                          ENTRY_WIDTH_PIPS,     // 何PIPSの間隔をあけるか
                          mMarketinfoMODE_BID); // 発注予定値
      if(flag_is_TradablePrice == false) {
printf( "[%d]EI トレーディングラインでシグナル消滅　現在=%s ショート最大=%s 　最小=%s" , __LINE__,
         DoubleToString(mMarketinfoMODE_BID, 5), DoubleToString(short_Max, 5), DoubleToString(short_Min, 5));            
      
         buysellSignal = NO_SIGNAL;
      }
   }

   // オシレータ系テクニカル指標を使った売買判断
   int WPR_Signal;
   int RSI_Signal;
   int STOC_Signal;
   int Total_Signal;
   if(buysellSignal == BUY_SIGNAL || buysellSignal == SELL_SIGNAL) {
      int flagOsci = judge_BuySellSignal_Oscillator(global_Symbol,
                                                    WPR_Signal, // WPRを使ったシグナル。BUY_SIGNAL, SELL_SIGNAL, NO_SIGNAL
                                                    RSI_Signal, // RSIを使ったシグナル。BUY_SIGNAL, SELL_SIGNAL, NO_SIGNAL
                                                    STOC_Signal, // Stochasticを使ったシグナル。BUY_SIGNAL, SELL_SIGNAL, NO_SIGNAL
                                                    Total_Signal // 3つのシグナルのうち1つ以上がBUY_SIGNALかつSELL_SIGNALが無ければ、BUY_SIGNAL
                                      );

      if(buysellSignal == BUY_SIGNAL && flagOsci == SELL_SIGNAL) {
printf( "[%d]EI オシレータでシグナル消滅" , __LINE__);            
      
         buysellSignal = NO_SIGNAL;
      }
      else if(buysellSignal == SELL_SIGNAL && flagOsci == BUY_SIGNAL) {
printf( "[%d]EI オシレータでシグナル消滅" , __LINE__);                  
         buysellSignal = NO_SIGNAL;         
      }
   }
   
   datetime tradeTime = Time[0];
   if(TrendBBTime0 != tradeTime) {
      if( buysellSignal == BUY_SIGNAL) {
   
         tp = mMarketinfoMODE_ASK + NormalizeDouble(change_PiPS2Point(TP_PIPS), global_Digits); // 利確の候補
         sl = mMarketinfoMODE_ASK - NormalizeDouble(change_PiPS2Point(SL_PIPS), global_Digits); // 損切の候補 
      
         ticket_num = mOrderSend5(global_Symbol,OP_BUY,LOTS,mMarketinfoMODE_ASK,SLIPPAGE, sl, tp,changeMagicToString(mMagic),mMagic,0, LINE_COLOR_LONG);	
         if(ticket_num > 0){
            TrendBBTime0 = tradeTime;
         }
         else if(ticket_num == ERROR_ORDERSEND) {
            printf( "[%d]エラー 買い発注の失敗::%d" , __LINE__ , ticket_num);
            return false;
         } 
      }
      else if(buysellSignal == SELL_SIGNAL) {
         tp = mMarketinfoMODE_BID - NormalizeDouble(change_PiPS2Point(TP_PIPS), global_Digits); // 利確の候補
         sl = mMarketinfoMODE_BID + NormalizeDouble(change_PiPS2Point(SL_PIPS), global_Digits); // 損切の候補 
         
         ticket_num = mOrderSend5(global_Symbol,OP_SELL,LOTS,mMarketinfoMODE_BID,SLIPPAGE,sl, tp,changeMagicToString(mMagic),mMagic,0,LINE_COLOR_SHORT);
         if(ticket_num > 0) {
            TrendBBTime0 = tradeTime;
         }
         else if(ticket_num == ERROR_ORDERSEND) {
            printf( "[%d]エラー 売り発注の失敗::%d" , __LINE__ , ticket_num);
            return false;
         } 
      }
   }
   else {
      return false;
   }
   return false;   
   
}







//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|   共通関数　　　                                                 |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//|   定時メール送信                                                 |
//+------------------------------------------------------------------+	

//+------------------------------------------------------------------+
//| マジックナンバー（数値）を戦略名（文字列）に変換する　　　                     　　　　　      |
//+------------------------------------------------------------------+
string changeMagicToString(int mag) {
   string strBuf = "";
if(mag == MagicNumberTrendEI) {
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

// st_Strategyの初期化
void init_st_Strategy(){
   int i;
   for(i = 0; i < MAX_STRATEGIES; i++) {
      init_st_Strategy(i);
   }
}

void init_st_Strategy(int mIndex){
   st_Strategies[mIndex].buysellSignal = NO_SIGNAL;
   st_Strategies[mIndex].signalTime    = -1;
   st_Strategies[mIndex].lastCheckTime = -1;
   st_Strategies[mIndex].point         = INT_VALUE_MAX;
   if(mIndex == 0) {
      st_Strategies[mIndex].strategy = "TB";
   }
   else if(mIndex == 1) {
      st_Strategies[mIndex].strategy = "SR";
   }
   else if(mIndex == 2) {
      st_Strategies[mIndex].strategy = "MRA";
   }
   else if(mIndex == 3) {
      st_Strategies[mIndex].strategy = "PB";
   }
   else if(mIndex == 4) {
      st_Strategies[mIndex].strategy = "WP";
   }
   else if(mIndex == 5) {
      st_Strategies[mIndex].strategy = "CR";
   }
   else if(mIndex == 6) {
      st_Strategies[mIndex].strategy = "KG";
   } 

}

struct st_TradeHistory {  // 取引を行う3つの通貨ペアと通貨ペア1,2の相関係数、最後に取引をした時刻を持つ構造体。
   string   strategy_name;
   int      buysell_flag; // BUY_SIGNAL, SELL_SIGNAL, NO_SIGNAL
   datetime open_time;    // 発生時刻
   double   open_price;   // 発生時取引値
   double   take_profit;  // 利益確定値
   double   stop_loss;    // 損失確定値
   datetime close_time;   // 決済時刻
   double   close_price;  // 決済値
   double   pl;           // 損益（ポイント）＝123.456ロング、123.461決済時は+0.005
   
};
st_TradeHistory st_TradeHistories[MAX_ARRAY_NUM];

void init_st_TradeHistories() {
   int i;
   for(i = 0; i < MAX_ARRAY_NUM ;i++) {
      init_st_TradeHistories(i);
   }
}
void init_st_TradeHistories(int mIndex) {
   st_TradeHistories[mIndex].strategy_name = "";
   st_TradeHistories[mIndex].buysell_flag  = NO_SIGNAL;
   st_TradeHistories[mIndex].open_time     = 0;
   st_TradeHistories[mIndex].open_price    = 0.0;
   st_TradeHistories[mIndex].take_profit   = 0.0;
   st_TradeHistories[mIndex].stop_loss     = 0.0;
   st_TradeHistories[mIndex].close_time   = 0;
   st_TradeHistories[mIndex].close_price   = 0.0;
   st_TradeHistories[mIndex].pl            = 0.0;
}

// 仮想取引の登録
// 各戦略で個別に売買フラグが発生した場合に、この関数を呼ぶ。
// 関数呼び出し時点の取引値、利確、損切値を使って仮想取引を追加する。
// 仮想取引の登録に成功したらtrueを返す。それ以外はfalseを返す。
bool add_st_TradeHistories(string   mStrategy,  // 戦略名
                           int      mBuysell   // 売買フラグ
                          ) {
   int i;
   datetime timeNow = iTime(Symbol(), PERIOD_CURRENT, 0);
   
   // 同じ戦略名、売買フラグ、発生時刻のデータが存在すればtrueを返して終了。
   for(i = 0; i < MAX_ARRAY_NUM; i++) {
      if(StringCompare(st_TradeHistories[i].strategy_name, mStrategy) == 0
         && st_TradeHistories[i].buysell_flag == mBuysell
         && st_TradeHistories[i].open_time == timeNow) {
         return true;
      }
   }
   
   // st_TradeHistories[i]の空きを探す。
   for(i = 0; i < MAX_ARRAY_NUM; i++) {
      if(StringLen(st_TradeHistories[i].strategy_name) <= 0) {
         st_TradeHistories[i].strategy_name = mStrategy;
         st_TradeHistories[i].buysell_flag  = mBuysell;
         st_TradeHistories[i].open_time     = timeNow;
         st_TradeHistories[i].open_price    = iClose(Symbol(), PERIOD_CURRENT, 0);
         if(mBuysell == BUY_SIGNAL) {
            st_TradeHistories[i].take_profit   = st_TradeHistories[i].open_price + change_PiPS2Point(TP_PIPS);
            st_TradeHistories[i].stop_loss     = st_TradeHistories[i].open_price - change_PiPS2Point(SL_PIPS);
         }
         else if(mBuysell == SELL_SIGNAL) {
            st_TradeHistories[i].take_profit   = st_TradeHistories[i].open_price - change_PiPS2Point(TP_PIPS);
            st_TradeHistories[i].stop_loss     = st_TradeHistories[i].open_price + change_PiPS2Point(SL_PIPS);
         }
         else {
            return false;
         }
         st_TradeHistories[i].close_time   = 0;
         st_TradeHistories[i].close_price   = 0.0;
         st_TradeHistories[i].pl            = 0.0;      
         
         return true;
      }
      
   }
   // 空きがなければ一番古いデータを削除して再実行する。
   datetime oldestTradeTime = INT_MAX;
   int      oldestTradeIndex = -1;
   for(i = 0; i < MAX_ARRAY_NUM; i++) {
      if(st_TradeHistories[i].open_time < oldestTradeTime) {
         oldestTradeTime = st_TradeHistories[i].open_time;
         oldestTradeIndex = i;
      }
   }
   if(oldestTradeTime == INT_MAX || oldestTradeIndex < 0) {
      printf( "[%d]EIエラー st_TradeHistories配列があふれている" , __LINE__);
      return false;
   }
   else {
      init_st_TradeHistories(oldestTradeIndex);
      add_st_TradeHistories(mStrategy, mBuysell);
   }
   
   return true;
}                          

// 仮想取引の更新
// 関数呼び出し時点の取引値で利確、損切を判断する。
void update_st_TradeHistories() {
   int i;
   double closeValue = iClose(Symbol(), PERIOD_CURRENT, 0);
   datetime timeNow  = iTime(Symbol(), PERIOD_CURRENT, 0);
   for(i = 0; i < MAX_ARRAY_NUM; i++) {
      if(StringLen(st_TradeHistories[i].strategy_name) <= 0
         || st_TradeHistories[i].close_time > 0
         ) {
         continue;
      }
      
      if(st_TradeHistories[i].buysell_flag == BUY_SIGNAL) {  
         if(closeValue > st_TradeHistories[i].take_profit
            || closeValue < st_TradeHistories[i].stop_loss
            ) {
            st_TradeHistories[i].close_time = timeNow;
            st_TradeHistories[i].pl         = closeValue - st_TradeHistories[i].open_price;
         }
      }
      else if(st_TradeHistories[i].buysell_flag == SELL_SIGNAL) {
         if(closeValue < st_TradeHistories[i].take_profit
            || closeValue > st_TradeHistories[i].stop_loss
            ) {
            st_TradeHistories[i].close_time = timeNow;
            st_TradeHistories[i].pl         = st_TradeHistories[i].open_price - closeValue;
         }
      }
   }
}

// 仮想取引の勝敗計算
// 関数呼び出し時点の勝ち数、負け数、利益合計、損失合計を引数で返す。
void get_Results(string mStrategy, // 戦略名
                 int    &mWinNum,  // 勝ち数
                 int    &mLoseNum, // 敗け数
                 double &mProfit,  // 利益合計
                 double &mLoss     // 損失合計
                 ) {
   int i;
   mWinNum  = 0;
   mLoseNum = 0;
   mProfit  = 0.0;
   mLoss    = 0.0;
   for(i = 0; i < MAX_ARRAY_NUM; i++) {
      if(StringCompare(st_TradeHistories[i].strategy_name, mStrategy) == 0
         && st_TradeHistories[i].close_time > 0) {
         if(st_TradeHistories[i].pl >= 0.0) {
            mWinNum += 1;
            mProfit += st_TradeHistories[i].pl;
         }
         else {
            mLoseNum += 1;
            mLoss += st_TradeHistories[i].pl;
         }
      }
   }
}


void update_st_Strategy(string   mStrategy,
                        int      mbuysellSignal,
                        datetime msignalTime
                        ){
   int i;
   datetime timeNow = iTime(Symbol(), PERIOD_CURRENT, 0);
   for(i = 0; i < MAX_STRATEGIES; i++) {
      // 空欄は無い前提だが、もし存在したら飛ばす。
      if(StringLen(st_Strategies[i].strategy) <= 0) {
         continue;
      }
      // 直近の判定時刻から時間が経っていない場合は飛ばす。
      if(StringCompare(st_Strategies[i].strategy, mStrategy) == 0) {
         if(st_Strategies[i].lastCheckTime >= iTime(Symbol(), PERIOD_CURRENT, 0)) {
            break;
         }
      }
            
      // 引数と同じ戦略名の要素を見つけたらフラグを上書きセットする。
      // 合わせて仮想取引を登録する。
      if(StringCompare(st_Strategies[i].strategy, mStrategy) == 0) {
         if(mbuysellSignal == BUY_SIGNAL || mbuysellSignal == SELL_SIGNAL) {
            add_st_TradeHistories(mStrategy, mbuysellSignal);
            st_Strategies[i].buysellSignal = mbuysellSignal;
            st_Strategies[i].signalTime    = msignalTime;
            st_Strategies[i].point         = 0; // フラグ設定時点ではポイントは0
            st_Strategies[i].lastCheckTime = timeNow;
            break;
         }
         // NO_SIGNALの時はポイントの更新だけを行う。
         else {
            st_Strategies[i].point         = timeNow - st_Strategies[i].signalTime;
            if(st_Strategies[i].point > G_SIGNAL_LIFE) {
               st_Strategies[i].buysellSignal = NO_SIGNAL;
               st_Strategies[i].signalTime    = -1;
               st_Strategies[i].point         = INT_VALUE_MAX;  
            }
            break;
         }
      }
   }

   //for(i = 0; i < MAX_STRATEGIES; i++) {
   //   if(StringLen(st_Strategies[i].strategy) <= 0) {
   //      break;
   //   }
   //   if(st_Strategies[i].signalTime >= 0
   //      && (st_Strategies[i].buysellSignal == BUY_SIGNAL || st_Strategies[i].buysellSignal == SELL_SIGNAL) 
   //      ) {
   //      st_Strategies[i].barNum     = iBarShift(Symbol(), PERIOD_CURRENT, st_Strategies[i].signalTime, false);
   //      st_Strategies[i].signalTime = msignalTime;
   //      st_Strategies[i].point      = st_Strategies[i].barNum;
   //   }
   //}
   //   update_st_Strategy_ShiftPoint();
}

void update_st_Strategy_ShiftPoint() {
   int i;
   datetime timeNow = iTime(Symbol(), PERIOD_CURRENT, 0);
      
   for(i = 0; i < MAX_STRATEGIES; i++) {
      if(StringLen(st_Strategies[i].strategy) <= 0) {
         continue;
      }
      
      // 売買フラグが設定されている戦略のデータを更新する。
      if(st_Strategies[i].signalTime >= 0
         && (st_Strategies[i].buysellSignal == BUY_SIGNAL || st_Strategies[i].buysellSignal == SELL_SIGNAL) 
         ) {
// printf( "[%d]EI >%s<の売買フラグの寿命＝＝%d" , __LINE__ , st_Strategies[i].strategy, timeNow - st_Strategies[i].signalTime);
         if(timeNow - st_Strategies[i].signalTime > G_SIGNAL_LIFE) {
// printf( "[%d]EI >%s<の売買フラグの寿命が尽きたのでフラグをクリア" , __LINE__ , st_Strategies[i].strategy);
            st_Strategies[i].buysellSignal = NO_SIGNAL;
            st_Strategies[i].signalTime    = -1;
            st_Strategies[i].point         = INT_VALUE_MAX;  
         }
      }
      else {
         st_Strategies[i].buysellSignal = NO_SIGNAL;
         st_Strategies[i].signalTime    = -1;
         st_Strategies[i].point         = INT_VALUE_MAX;      
      }
   }
}


void overwrite_ExternalParams(double mTP_PIPS,
                              double mSL_PIPS,
                              double mFlooring,
                              bool   mFlooring_continue,
                              double mShort_Entry_With_PER,
                              double mLong_Entry_With_PER
                              ) {
   BUF_TP_PIPS = TP_PIPS ;  
   TP_PIPS     = mTP_PIPS;

   BUF_SL_PIPS = SL_PIPS;
   SL_PIPS     = mSL_PIPS;  

   BUF_FLOORING = FLOORING;
   FLOORING     = mFlooring;

   BUF_FLOORING_CONTINUE = FLOORING_CONTINUE;
   FLOORING_CONTINUE     = mFlooring_continue;

//   BUF_SHORT_ENTRY_WIDTH_PER = SHORT_ENTRY_WIDTH_PER;
//   SHORT_ENTRY_WIDTH_PER     = mShort_Entry_With_PER;
//
//   BUF_LONG_ENTRY_WIDTH_PER = LONG_ENTRY_WIDTH_PER; 
//   LONG_ENTRY_WIDTH_PER     = mLong_Entry_With_PER;
}

//
// 外部パラメーターに対してグローバル変数に上書きした値を元に戻す。
void recovery_ExternalParams() {
   TP_PIPS     = BUF_TP_PIPS ;
   SL_PIPS     = BUF_SL_PIPS;
   FLOORING    = BUF_FLOORING;
   FLOORING_CONTINUE     = BUF_FLOORING_CONTINUE;
   //SHORT_ENTRY_WIDTH_PER = BUF_SHORT_ENTRY_WIDTH_PER;
   //LONG_ENTRY_WIDTH_PER  = BUF_LONG_ENTRY_WIDTH_PER; 
}


// st_Strategyの値を使って売買シグナルを返す。
// ・毎時、各戦略で売買シグナルを計算する。
// ・計算した売買シグナル、時刻を更新する。
// ・シグナルが発生した時刻が何シフト前かと持ち点を更新する。
// ・NO_SIGNALを除いて、
//  - 全戦略の売買シグナルが同じ（売り又は買い）
// 　- 2つ以上の戦略が同じ（売り又は買い）
// 　- 持ち点合計が規定値未満
// 　であれば、売買シグナルを確定する。
int get_Signal_from_st_Strategy() {
   int i;
   int ret = NO_SIGNAL;
   int totalPoint = 0;
   int buySignalNum = 0; // 買いシグナルがあった戦略数
   double buySignalTotal = 0;  // 買いシグナルのポイント合計
   int sellSignalNum = 0; // 売りシグナルがあった戦略数
   double sellSignalTotal = 0;  // 売りシグナルのポイント合計
   
   for(i = 0; i < MAX_STRATEGIES; i++) {
      if(StringLen(st_Strategies[i].strategy) <= 0) {
         continue;
      }
      
      /*printf( "[%d]EI %s時点のst_Strategies[%d] 戦略=>%s< シグナル>%d< ロングは%dショートは%d 時刻=%d=%s ポイント=%s" , __LINE__, TimeToString(Time[0]),i, 
              
              st_Strategies[i].strategy,
              st_Strategies[i].buysellSignal, BUY_SIGNAL, SELL_SIGNAL,
              st_Strategies[i].signalTime, TimeToString(st_Strategies[i].signalTime),
              DoubleToString(st_Strategies[i].point, 1)
              
              );
              */
      if(st_Strategies[i].buysellSignal == BUY_SIGNAL) {
// printf( "[%d]EI %s 戦略名>%s<は買いフラグ　ポイント=>%d<" , __LINE__ , TimeToString(iTime(Symbol(), PERIOD_CURRENT, 0)), st_Strategies[i].strategy, st_Strategies[i].point);
         buySignalNum++;
         buySignalTotal = buySignalTotal + st_Strategies[i].point;
      }
      else if(st_Strategies[i].buysellSignal == SELL_SIGNAL) {
// printf( "[%d]EI %s 戦略名>%s<は売りフラグ　ポイント=>%d<" , __LINE__ , TimeToString(iTime(Symbol(), PERIOD_CURRENT, 0)), st_Strategies[i].strategy, st_Strategies[i].point);
         sellSignalNum++;
         sellSignalTotal = sellSignalTotal + st_Strategies[i].point;
      }
   }
//printf( "[%d]EI %s 買いシグナルの件数=>%d< 買いポイント合計=>%d<　売りシグナルの件数=>%d< 売りポイント合計=>%d<" , __LINE__ , 
//      TimeToString(iTime(Symbol(), PERIOD_CURRENT, 0)), 
//      buySignalNum,  buySignalTotal, 
//      sellSignalNum, sellSignalTotal);
   

   ret = NO_SIGNAL;
   // ロング、ショート各々が0件の時は、シグナルなしと判断する。
   if(buySignalNum <= 0 && sellSignalNum <= 0) {
      ret = NO_SIGNAL;
   }
   // 両方のシグナルが発生している場合は、シグナルなしと判断する。
   else if(buySignalNum > 0 && sellSignalNum > 0) {
printf( "[%d]EI 売買の両方が発生しているのでシグナル消滅。　　%s 買いシグナルの件数=>%d< 買いポイント合計=>%d<　売りシグナルの件数=>%d< 売りポイント合計=>%d<" , __LINE__ , 
      TimeToString(iTime(Symbol(), PERIOD_CURRENT, 0)), 
      buySignalNum,  buySignalTotal, 
      sellSignalNum, sellSignalTotal);

      ret = NO_SIGNAL;   
      
   }
   else if(buySignalNum >= 1 && sellSignalNum == 0 && buySignalTotal <  G_TRADE_BORDER) {
      ret = BUY_SIGNAL;
   }
   else if(buySignalNum >= 1 && sellSignalNum == 0 && buySignalTotal >=  G_TRADE_BORDER) {
printf( "[%d]EI 買いの合計が%dを超えたのでシグナルなし。　　%s 買いシグナルの件数=>%d< 買いポイント合計=>%d<　売りシグナルの件数=>%d< 売りポイント合計=>%d<" , __LINE__ , G_TRADE_BORDER,
      TimeToString(iTime(Symbol(), PERIOD_CURRENT, 0)), 
      buySignalNum,  buySignalTotal, 
      sellSignalNum, sellSignalTotal);
   }
   else if(sellSignalNum >= 1 && buySignalNum == 0 &&  sellSignalTotal <  G_TRADE_BORDER) {
      ret = SELL_SIGNAL;
   }
   else if(sellSignalNum >= 1 && buySignalNum == 0 &&  sellSignalTotal >=  G_TRADE_BORDER) {
printf( "[%d]EI 売りの合計が%dを超えたのでシグナルなし。　　%s 買いシグナルの件数=>%d< 買いポイント合計=>%d<　売りシグナルの件数=>%d< 売りポイント合計=>%d<" , __LINE__ , G_TRADE_BORDER,
      TimeToString(iTime(Symbol(), PERIOD_CURRENT, 0)), 
      buySignalNum,  buySignalTotal, 
      sellSignalNum, sellSignalTotal);
   }

   //
   // スワップが正の時だけ取引する。
   //
   //
   if(TRADE_PLUS_SWAP == true) {
      if(ret == BUY_SIGNAL && SymbolInfoDouble(Symbol(), SYMBOL_SWAP_LONG) < 0) {
         ret = NO_SIGNAL;
      }
      else if(ret == SELL_SIGNAL && SymbolInfoDouble(Symbol(), SYMBOL_SWAP_SHORT) < 0) {
         ret = NO_SIGNAL;
      }
   }
if(ret == BUY_SIGNAL) {
printf( "[%d]EI 買いシグナル発生中" , __LINE__);
}      
else if(ret == SELL_SIGNAL) {
printf( "[%d]EI 売りシグナル発生中" , __LINE__);
}      


   return ret;
}


void output_st_Strategies() {
   int i;
   printf( "[%d]EI st_Strategies[n] 戦略名, 売買, 発生時刻, ポイント" , __LINE__);
   for(i = 0; i < MAX_STRATEGIES; i++) {
      if(StringLen(st_Strategies[i].strategy) <= 0) {
         continue;
      }
      
      printf( "[%d]EI st_Strategies[%d] %s, %d, %s, %d" , __LINE__ , i, 
                 st_Strategies[i].strategy, 
                 st_Strategies[i].buysellSignal,
                 TimeToString(st_Strategies[i].signalTime),
                 st_Strategies[i].point);
   }
}

void output_st_TradeHistories(){
   int i;
   printf( "[%d]EI st_TradeHistories[n] 戦略名, 売買, 発生時刻, 発生価格, 利確値, 損切値, 決済時刻, 決済値, 損益" , __LINE__);

   for(i = 0; i < MAX_STRATEGIES; i++) {
      if(StringLen(st_TradeHistories[i].strategy_name) <= 0) {
         continue;
      }
      
      printf( "[%d]EI st_TradeHistories[%d] %s, %d, %s, %s, %s, %s, %s, %s, %s," , __LINE__ , i, 
                 st_TradeHistories[i].strategy_name,
                 st_TradeHistories[i].buysell_flag,
                 TimeToString(st_TradeHistories[i].open_time),
                 DoubleToString(st_TradeHistories[i].open_price, 5),
                 DoubleToString(st_TradeHistories[i].take_profit, 5),
                 DoubleToString(st_TradeHistories[i].stop_loss, 5),
                 TimeToString(st_TradeHistories[i].close_time),
                 DoubleToString(st_TradeHistories[i].close_price, 5),
                 DoubleToStr(st_TradeHistories[i].pl, 5));
   }
}
