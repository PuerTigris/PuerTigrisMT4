// 20230811 ティック単位で(G_CONTINUE_NUM+2)回以上連続して上昇していれば買い、連続して下降していれば売り。

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

//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
extern int    MagicNumberNP        = 90000025;
//

//
extern string PuerTigrisNPTitle    = "---NPのパラメータ---";
extern int    G_CONTINUE_NUM       = 1;   // 何回連続して上昇・下降したら取引するかの回数。1に加える回数。
extern int    G_MAX_OPEN_TRADENUM  = 999;
extern double G_SL_NUM = 1.0; // 損切は利確の何倍か

//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
string PGName = "PuerTigris"; //プログラム名	

datetime NPtime0 = 0;//足1本で1回の処理をするための変数
int continue_counter = 0;        // 連続上昇・下降回数。連続上昇中の時は正で増加、連続下降中の時は負で減少。
double continue_div_total = 0.0; // 連続上昇・下降中の変化量の合計 
double continue_previous_close = 0.0; // 連続上昇・下降中の直前のclose値
datetime continue_previous_time = 0; //
//+------------------------------------------------------------------+	
//| 初期処理                                                         |	
//+------------------------------------------------------------------+	
int init() {	
   //オブジェクトの削除	
   MyObjectsDeleteAll();

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
                                                   
   continue_counter = 0;
   continue_div_total = 0.0;
   continue_previous_close = 0.0;
   continue_previous_time = 0;
   return(INIT_SUCCEEDED);	
}	
	
//+------------------------------------------------------------------+	
//| 終了処理                                                         |	
//+------------------------------------------------------------------+	
int deinit() {	
   //オブジェクトの削除	
   MyObjectsDeleteAll();

   return(0);	
}	
	
//+------------------------------------------------------------------+	
//| メイン処理                                                       |	
//+------------------------------------------------------------------+	
int start()	
{


   //変数宣言　　	
   double tmpBID = 0.0;
   double tmpASK = 0.0;
   ENUM_TIMEFRAMES TIME_FRAME_MAXMIN_ENUM = changeInt2ENUMTIMEFRAME(TIME_FRAME_MAXMIN);

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


   int openTradeNum = -1;
  
   openTradeNum = get_OpenTradeNum(MagicNumberNP);
   if(openTradeNum < G_MAX_OPEN_TRADENUM && is_TradablePrice() > 0) {
      entryNP(MagicNumberNP);
   }
   else {
      printf( "[%d] 同時オープン可能な%d件をオーバーするため、実取引の検討せず。" , __LINE__ , G_MAX_OPEN_TRADENUM);
   }

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、全オーダーの指値と逆指値をセットする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      update_AllOrdersTPSL(global_Symbol, MagicNumberNP, TP_PIPS, SL_PIPS);
   } 

   //最小利食値FLOORINGが設定されていれば、損切値の更新を試す。
   if(FLOORING >= 0) {
      flooringSL(global_Symbol, MagicNumberNP, FLOORING, FLOORING_CONTINUE);
   }

   //TP_PIPSかSL_PIPSのどちらかが0より大きければ、マジックナンバーをキーとして強制決済をする。	
   if(TP_PIPS > 0 || SL_PIPS > 0) {		
      do_ForcedSettlement(MagicNumberNP, global_Symbol, TP_PIPS, SL_PIPS);
   } 
   return(0);	
}	
	

////
//// 外部パラメータをグローバル変数にコピーする。
////
//void update_GlobalParam_to_ExternalParam() {
//   PinBarMethod       = G_PinBarMethod;       // 計算ロジック1～7
//                                              // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5
//                                              // 110(6)=No3とNo5, 111(7)=No1とNo3とNo5  
//   PinBarTimeframe    = G_PinBarTimeframe;    // 計算に使う時間軸。1～9
//   PinBarBackstep     = G_PinBarBackstep;     // 大陽線、大陰線が発生したことを何シフト前まで確認するか
//   PinBarBODY_MIN_PER = G_PinBarBODY_MIN_PER; // 実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
//   PinBarPIN_MAX_PER  = G_PinBarPIN_MAX_PER;  // 実体が髭のナンパ―セント以下であればピンと判断するか
//}


//+------------------------------------------------------------------+
//| 実験中      　　　　      |
//+------------------------------------------------------------------+
bool entryNP(int mMagic) {

   // 戦略別mqhの関数を使用する。
   int buysellSignal = entryNP();

   int intTrend = NoTrend;
   bool mFlag = false;
   double sl = 0.0;
   double tp = 0.0;
   int ticket_num = 0;
   
   if( (buysellSignal == BUY_SIGNAL || buysellSignal == SELL_SIGNAL ) && continue_counter != 0) {
   
      double mMarketinfoMODE_ASK = 0.0;
      double mMarketinfoMODE_BID = 0.0;
   
      
      datetime tradeTime = Time[0];
      double local_stoplevel = 0.0;
   
      if(NPtime0 != tradeTime) {
         if( buysellSignal == BUY_SIGNAL) {
            local_stoplevel     = change_PiPS2Point(MarketInfo(Symbol(),MODE_STOPLEVEL));
            mMarketinfoMODE_ASK = MarketInfo(Symbol(),MODE_ASK);
            mMarketinfoMODE_BID = MarketInfo(Symbol(),MODE_BID);
//printf( "[%d]tp確認用　mMarketinfoMODE_ASK=>%s< 平均=>%s<÷>%d< = >%s<  ストップレベル=>%s<" , __LINE__ , 
//        DoubleToString(mMarketinfoMODE_ASK, 5), 
//        DoubleToString(continue_div_total, 5),continue_counter, DoubleToString(NormalizeDouble(continue_div_total / continue_counter, Digits()), 5),
//        DoubleToString(local_stoplevel, 5)
//        );
            tp = mMarketinfoMODE_ASK + NormalizeDouble(continue_div_total / continue_counter, Digits()); //　ストップレベルを無視。強制決済に依存。
            sl = mMarketinfoMODE_BID - NormalizeDouble(continue_div_total / continue_counter, Digits()) * G_SL_NUM; //　ストップレベルを無視。強制決済に依存。
            //tp = mMarketinfoMODE_ASK + NormalizeDouble(continue_div_total / continue_counter, Digits()) + local_stoplevel;
            //sl = mMarketinfoMODE_BID - NormalizeDouble(continue_div_total / continue_counter, Digits()) - local_stoplevel;
    
            ticket_num = mOrderSend5(global_Symbol,OP_BUY,LOTS,mMarketinfoMODE_ASK,SLIPPAGE, sl, tp,changeMagicToString(mMagic),mMagic,0, LINE_COLOR_LONG);	
            if(ticket_num > 0){
               NPtime0 = tradeTime;
            }
            else if(ticket_num == ERROR_ORDERSEND) {
               printf( "[%d]エラー 買い発注の失敗::%d" , __LINE__ , ticket_num);
               return false;
            } 
         }
         else if(buysellSignal == SELL_SIGNAL) {
            local_stoplevel     = change_PiPS2Point(MarketInfo(Symbol(),MODE_STOPLEVEL));
            mMarketinfoMODE_ASK = MarketInfo(Symbol(),MODE_ASK);
            mMarketinfoMODE_BID = MarketInfo(Symbol(),MODE_BID);
   
            tp = mMarketinfoMODE_BID - MathAbs(NormalizeDouble(continue_div_total / continue_counter, Digits())) ;//　ストップレベルを無視。強制決済に依存。
            sl = mMarketinfoMODE_ASK + MathAbs(NormalizeDouble(continue_div_total / continue_counter, Digits())) * G_SL_NUM;//　ストップレベルを無視。強制決済に依存。
//            tp = mMarketinfoMODE_BID - MathAbs(NormalizeDouble(continue_div_total / continue_counter, Digits())) - local_stoplevel;
//            sl = mMarketinfoMODE_ASK + MathAbs(NormalizeDouble(continue_div_total / continue_counter, Digits())) + local_stoplevel;
            
            ticket_num = mOrderSend5(global_Symbol,OP_SELL,LOTS,mMarketinfoMODE_BID,SLIPPAGE,sl, tp,changeMagicToString(mMagic),mMagic,0,LINE_COLOR_SHORT);
            if(ticket_num > 0) {
               NPtime0 = tradeTime;
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
   }
   return false;   
   
}


// ティック単位で(G_CONTINUE_NUM+2)回以上連続して上昇していれば買い、連続して下降していれば売り。
int entryNP() {
   double currClose = iClose(Symbol(), 0, 0);
   
   // 直前のclose値が設定されていなければ、上昇も下降も判断せず、NO_SIGNALを返す。
   if(continue_previous_close <= 0.0) {
      continue_previous_close = currClose;
      continue_previous_time = iTime(Symbol(), 0, 0);
      return NO_SIGNAL;
   }

//printf( "[%d]シグナル判定確認　直前の時間=>%d<=>%s< 直前の値=>%s<   最新の時間=>%d<=>%s< 最新の値=>%s<" , __LINE__ ,
//         continue_previous_time, TimeToString(continue_previous_time), DoubleToString(continue_previous_close, 5),
//         iTime(Symbol(), 0, 0), TimeToString(iTime(Symbol(), 0, 0)),DoubleToString(currClose, 5)
//         );
   
   // 現時点のCloseが直前より大きい時
   if(currClose >= continue_previous_close) {
      // 直前まで連続下降中だった場合
      if(continue_counter < 0) {
         continue_counter = 1; // 連続下降から連続上昇に変更
         continue_div_total = currClose - continue_previous_close;
      }
      // 連続上昇が継続する場合。
      else {
//printf( "[%d]連続上昇中　>%d<回 差分合計は >%s< + >%s< = >%s<" , __LINE__ , continue_counter + 1, 
//         DoubleToString(continue_div_total, 5),
//         DoubleToString((currClose - continue_previous_close), 5),
//         DoubleToString(continue_div_total + (currClose - continue_previous_close), 5)
//       );
       
         continue_counter = continue_counter + 1; // 連続上昇を更新
         continue_div_total = continue_div_total + (currClose - continue_previous_close);
      }
   }
   // 現時点のCloseが直前より小さい時
   else if(currClose < continue_previous_close) {
//printf( "[%d]連続上昇キャンセル" , __LINE__);
   
      // 直前まで連続上昇中だった場合
      if(continue_counter > 0) {
         continue_counter = -1; // 連続下降から連続上昇に変更
         continue_div_total = currClose - continue_previous_close; // 下降中は、負になる。
      }
      // 連続下降が継続する場合。
      else {
         continue_counter = continue_counter - 1; // 連続下降を更新
         continue_div_total = continue_div_total + (currClose - continue_previous_close); // 負が追加される。
      }
   }
   // 直前のclose値を更新する。
   continue_previous_close = currClose;
   continue_previous_time = iTime(Symbol(), 0, 0);
   
   
   // 最小連続回数G_CONTINUE_NUMを超えていた時は、シグナル発生
   if(MathAbs(continue_counter) >= 1 + G_CONTINUE_NUM) {
      if(continue_counter > 0) {
         return BUY_SIGNAL;
      }
      else {
         return SELL_SIGNAL;
      }
   }
   
   return NO_SIGNAL;
}




//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|   共通関数　　　                                                 |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| マジックナンバー（数値）を戦略名（文字列）に変換する　　　                     　　　　　      |
//+------------------------------------------------------------------+
string changeMagicToString(int mag) {
   string strBuf = "";
if(mag == MagicNumberNP) {
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








