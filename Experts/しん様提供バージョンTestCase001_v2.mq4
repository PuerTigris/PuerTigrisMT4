//20221227 新規作成


//+------------------------------------------------------------------+	
//|  Copyright (c) 2016 トラの親 All rights reserved.                |	
//|                                                                  |
//+------------------------------------------------------------------+	
#property copyright "Copyright (c) 2016 トラの親 All rights reserved."				
#property link      "http://nenshuuha.blog.fc2.com/"		
//#property strict						
//+------------------------------------------------------------------+	
//| ヘッダーファイル読込                                             |	
//+------------------------------------------------------------------+	
#include <stderror.mqh>	
#include <stdlib.mqh>	


//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	
#define BUY_SIGNAL        1                //エントリーシグナル(ロング)	
#define SELL_SIGNAL      -1                //エントリーシグナル(ショート)
#define NO_SIGNAL         0                //エントリーシグナル(ロング、ショートいずれでもない)

#define LINE_COLOR_LONG    Blue
#define LINE_COLOR_SHORT   Red
#define LINE_COLOR_CLOSE   Violet
#define LINE_COLOR_DEFAULT Yellow

#define ERROR_ORDERSEND   -1
#define ERROR_ORDERMODIFY -2



//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
//
extern int    MagicNumberTestCase001 = 12345678;
extern int    SLIPPAGE    = 200;  // スリッページ
extern double SPREAD_PIPS = 200;  // スプレッド 
extern double LOTS        = 0.01; // オリジナル取引の取引ロット数
extern double LOTS_TIMES  = 2.0;  // ロットの倍数。損切した際に何倍返しにするか。
extern double MAX_Leverage= 25.0; // 最大レバレッジ。実効レバレッジがこの値を上回ったら、新規取引を中止する。
extern double TP_PIPS     = 3.0;  // 利益確定PIPS数
extern double SL_PIPS     = 3.0;  // 損失確定PIPS数

extern int    BUYSELL_TYPE_JUDGE_METHOD     = 6;     // 売買判定方法。-2から8(6推奨。ボリンジャーバンド逆張り)
//  -2:ショートのみ。-1:ロングのみ。0:ロング、ショートいづれも無し
//  1:4時間足のトレンド利用 2:上記1に加え、長短期移動平均利用   3:上記2に加え、長短期移動平均線が直前に交差
//  4:ランダム           5:ボリンジャーバンド（±3σ）利用―順張り  6:ボリンジャーバンド（±3σ）利用逆順張り 
//  7:ボリンジャーバンドとボラティリティを使った順張り＋逆張り          8:ローソクのヒゲ利用
extern bool   ONLY_ONE_ORIGINAL             = true;  // オリジナル取引の制限。(true推奨):オリジナル取引を１件のみ。
extern int    MAX_ADDITIONAL_TRADE_LEVEL    = 3;     // 倍返し制限回数。0以上(3推奨):継続取引の最大繰り返し回数。4の時、初期ロットが0.01とすると、0.02, 0.04, 0.08, 0.16まで繰り返す。
extern int    ADDITIONAL_TRADE_SWITCH       = 4;     // 倍返しの発生タイミング。1から4(4推奨):1:継続取引をしない。２：利確した時にのみ継続取引をする。３：損失が出た時にのみ継続取引をする。４：利確、損失共に継続取引をする。
extern bool   ADDITIONAL_TRADE_TYPE_SWITCH  = false; // 倍返し時の売買判定方法。(false推奨):継続取引の売買区分の判断にもオリジナル取引と同じ手法を反映させる。

//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
/////////////////////////////////////////////////////////////////////////
////////////////////////////Tigris_GLOBALS.mqhからコピー /////////////////
/////////////////////////////////////////////////////////////////////////
double ERROR_VALUE_DOUBLE =  999.999; // doubleを返す関数がエラーを返す時にこの値を使う
double DOUBLE_VALUE_MAX   =  999.999;
double DOUBLE_VALUE_MIN   = -999.999;
int    INT_VALUE_MAX      =  9999;
int    INT_VALUE_MIN      = -9999;

string global_Symbol    = Symbol();
int    global_Digits    = (int)MarketInfo(global_Symbol, MODE_DIGITS);
double global_Points    = MarketInfo(global_Symbol, MODE_POINT);  
double global_LotSize   = MarketInfo(global_Symbol, MODE_LOTSIZE);
double global_StopLevel = MarketInfo(global_Symbol, MODE_STOPLEVEL);
int    global_Period    = Period();

double SHORT_ENTRY_WIDTH_PER = 20.0; // ショート実施帯域。過去最高値から何パーセント下までショートするか
double LONG_ENTRY_WIDTH_PER  = 20.0; // ロング実施帯域。過去最安値から何パーセント上までロングするか

/////////////////////////////////////////////////////////////////////////
////////////////////////////Tigris_GLOBALS.mqhからコピー ここまで/////////////////
/////////////////////////////////////////////////////////////////////////

int    UpTrend   =  1; //上昇トレンド
int    DownTrend = -1; //下降トレンド
int    NoTrend   =  0; //トレンド無し

datetime TCTime0 = 0;
/*
string   global_Symbol = Symbol();
double   global_StopLevel = MarketInfo(global_Symbol, MODE_STOPLEVEL);
int      global_Digits    = (int)MarketInfo(global_Symbol, MODE_DIGITS);
*/
double   SPREAD_point;

int      Original_Trade_Num = 0; // 初期取引の個数
long      Original_Trade_Tick[9999]; // 初期取引のチケット番号
datetime CONTROLALLtime0    = 0;

//+------------------------------------------------------------------+	
//| 初期処理                                                         |	
//+------------------------------------------------------------------+	
int init() {
   int flagCheck = check_ExternalParam();
   if(flagCheck == INIT_FAILED) {
      return INIT_FAILED;
   }
   
//   SL_PIPS = TP_PIPS;
   
   Original_Trade_Num = 0;
   return(INIT_SUCCEEDED);	
}	
	
//+------------------------------------------------------------------+	
//| 終了処理                                                         |	
//+------------------------------------------------------------------+	
int deinit() {	

   return(0);	
}	
	
//+------------------------------------------------------------------+	
//| メイン処理                                                       |	
//+------------------------------------------------------------------+	
int start() {
   long ticketNum;

   // 処理を一定時間ごとにのみ行うためのフラグ設定
   // 例えば、ティックごとに行うと処理が重いので、１分おきに処理するなど。
   if(TimeCurrent() - CONTROLALLtime0 >= PERIOD_M1 * 60) { // 
      CONTROLALLtime0 = TimeCurrent();
   }
   else {
      return 1;
   }	


//   printf( ">%d<：：　OrdersTotal=%d件　  OrdersHistoryTotal=%d件" , __LINE__, OrdersTotal(), OrdersHistoryTotal());
   
   // 新規発注
   if(TCTime0 != Time[0]) {
      // オリジナル取引の数を取得する。
      long Original_Trade_Cand = get_OriginalTradeTick(MagicNumberTestCase001, // マジックナンバー
                                                      Original_Trade_Tick     // 出力：オリジナル取引のチケット番号一覧
                                                      );
/*
int i;
for(i = 0; i < Original_Trade_Cand; i++) {
   printf( ">%d<：：　オープン中のオリジナル取引=%d件　チケット=%d" , __LINE__, Original_Trade_Cand, Original_Trade_Tick[i]);
}
*/
      bool flag_OriginalTradeOpen = false;
      if(Original_Trade_Cand > 0) {
         //  オープン中の継続取引が存在しなければ、false 
         flag_OriginalTradeOpen = is_OriginalTradeOpen(MagicNumberTestCase001, // マジックナンバー
                                                       Original_Trade_Tick     // オリジナル取引のチケット番号一覧
                                                       ); 
      }

      if( (ONLY_ONE_ORIGINAL == true && flag_OriginalTradeOpen == false) 
            ||
          (ONLY_ONE_ORIGINAL == false) )  { 
         ticketNum = mOrderSend_OriginalTrade(MagicNumberTestCase001);
         TCTime0 = Time[0];
      }
   }
   
   // 決済処理
   bool flag;   
   flag = do_Settlement(MagicNumberTestCase001, ADDITIONAL_TRADE_SWITCH);
   return(0);	
}	

// １，とりあえず任意のタイミングで１単位ロング（またはショート）（利確も損切りも３ｐｉｐｓ）
// 【注意】実際には、利用するFX業者によりストップレベルが異なるため、3PIPSという狭い範囲で利確、損切設定は不可能。
//         そのため、関数で利確、損切を行う。
// ２，利確されたら、即同じ方向にポジションを取る（ロングポジションが利確になった場合は、即ロングポジションを取る。ショートはその逆。）
// ３，損切りになったら、即ドテンして反対方向にエントリーする（利確も損切りも同じく３ｐｉｐｓ）
//     （損切りになったら場合はドテン倍返しで、一度でも利確されたら１単位から再スタート）
// ４，以下これの繰り返し
bool do_Settlement(int mMagic, // マジックナンバー
                   int mMethod // 1:追加取引なし。２：利益が出た時の追加取引のみ実施。３：損失が出た時の反対売買のみ実施。４：全部あり
                  ) {
//printf( ">%d<：：do_Settlement実行時刻%s" , __LINE__, TimeToStr(Time[0]) );
                  
   // １　直前のCommentが空以外(= 直前の取引が2回目以降の継続取引。損失を繰り返した後の利益確定時には、継続取引をしない）
   // 　　１ー１　決済利益が出るとき
   // 　　　　　　直前のロットがLOTSの時（= 利益が出ているときの追加取引が連続中）　→　同じ売買区分、同じロット数で継続取引
   // 　　　　　　直前のロットがLOTS以外の時（= 損失確定後の繰り返し取引の利益確定）→　継続取引はしない
   // 　　１ー２　決済損失が出るとき　→　反対売買区分で、数倍したロット数で継続取引　　　
   // ２　直前のCommentが空(= 直前の取引が初回取引）
   // 　　２ー１　決済利益が出るとき　→　同じ売買区分、同じロット数で継続取引
   // 　　２ー２　決済損失が出るとき　→　反対売買区分で、数倍したロット数で継続取引                 
   double TP_Point = change_PIPS2Point(TP_PIPS);
   double SL_Point = change_PIPS2Point(SL_PIPS);
   int i;
   string comment_InitialOrNot = "";
   // 追加取引が可能かを調べる。
   bool flag_judge_Tradable = judge_Tradable(2);  // 取引可能な場合はtrue。不可能な場合はfalse。// 1:スプレッドのみ。2：スプレッドとレバレッジ
   string nextTradeComment;
   bool ret = true; // 一か所でも失敗すれば、false
   double mSELL_PL = 0.0;
   double mBUY_PL = 0.0;
   for(i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
         if(OrderMagicNumber() == mMagic && OrderCloseTime() <= 0
           && (OrderType() == OP_BUY || OrderType() == OP_SELL)
            ) {
            double mOpen    = NormalizeDouble(OrderOpenPrice(), global_Digits);
            int    mBuySell = OrderType();
            string mComment = OrderComment();
            double mLots    = OrderLots();
            int    mTick    = OrderTicket();

            // 評価損益を計算する。利確TP_Pointか損切SL_Pointを超えていたら、以下を続行）
            if(mBuySell == OP_BUY) {
               mBUY_PL = NormalizeDouble(Bid, global_Digits) - NormalizeDouble(mOpen, global_Digits); // ロングで利益が出ていれば正。損失が出ていれば負。

/*printf( ">%d<：：ロング　tick=>%d<の評価損益=BID>%s< - OPEN>%s< = %s :: SL_Point=%s   TP_Point=%s" , __LINE__,mTick, 
DoubleToStr(Bid, global_Digits),
DoubleToStr(mOpen, global_Digits),
DoubleToStr(mBUY_PL, global_Digits),
DoubleToStr(SL_Point, global_Digits),
DoubleToStr(TP_Point, global_Digits)
);*/

            }
            else if(mBuySell == OP_SELL) {
               mSELL_PL = NormalizeDouble(mOpen, global_Digits) - NormalizeDouble(Ask, global_Digits); // ショートで利益が出ていれば正。損失が出ていれば負。

/*printf( ">%d<：：ショート　tick=>%d<の評価損益=OPEN>%s< - ASK>%s<= %s :: SL_Point=%s   TP_Point=%s" , __LINE__,mTick, 
DoubleToStr(mOpen, global_Digits),
DoubleToStr(Ask, global_Digits),
DoubleToStr(mSELL_PL, global_Digits),
DoubleToStr(SL_Point, global_Digits),
DoubleToStr(TP_Point, global_Digits)
);*/

            }
            
            // if(StringCompare(OrderComment(), "") == 0) {
            if(StringLen(mComment) == 0) {
               // 追加取引発生元のマジックナンバー12345678<M>とチケットナンバー1<T>とロット数0.1<L>の順で、カンマ区切りで文字列を作成する。 12345678,1,0.1               
               nextTradeComment = IntegerToString(OrderMagicNumber()) + "," + IntegerToString(OrderTicket())+ "," + DoubleToStr(OrderLots(), global_Digits) ;
            }
            else {
               nextTradeComment = OrderComment();
            }
            

//printf( ">%d<確認" , __LINE__);
            
            // 評価利益が利確TP_Point未満かつ評価損失が損切SL_Pointであれば、
            // 利確、損切は発生しないため、後述の手続きをジャンプする。
            if( (mBuySell == OP_SELL) && (mSELL_PL < TP_Point && (mSELL_PL < 0.0 && MathAbs(mSELL_PL) < SL_Point)) ) {
/*printf( ">%d<：：ショート　mSELL_PL=>%s  TP_Point=>%s<  SL_Point=>%s<" , __LINE__,mTick, 
DoubleToStr(mSELL_PL, global_Digits),
DoubleToStr(TP_Point, global_Digits),
DoubleToStr(SL_Point, global_Digits)
);*/

            
               continue;
            }
            if( (mBuySell == OP_BUY)  && (mBUY_PL  < TP_Point && (mBUY_PL < 0.0  && MathAbs(mBUY_PL)  < SL_Point)) ) {
/*printf( ">%d<：：ロング　mSELL_PL=>%s  TP_Point=>%s<  SL_Point=>%s<" , __LINE__,mTick, 
DoubleToStr(mSELL_PL, global_Digits),
DoubleToStr(TP_Point, global_Digits),
DoubleToStr(SL_Point, global_Digits)
);*/
            
               continue;
            }
//printf( ">%d<確認" , __LINE__);
            
            // １　直前のCommentが空以外＝初回取引ではない
            int next_BuySell = NO_SIGNAL;
            int ticket_num;
            int revBuySell;
            // if(StringCompare(mComment, "") != 0) {
            if(StringLen(mComment) > 0) {
               // 　　１ー１　利益確定TP_Point以上の決済利益が出るとき
               // 　　　　　　①直前のロットがLOTSの時（= 利益が出ているときの追加取引が連続中）　→　同じ売買区分、同じロット数で継続取引
               // 　　　　　　②直前のロットがLOTS以外の時（= 反対売買後の利益確定）　　　　　　　→　継続取引はしない
               if( (mBuySell == OP_BUY  && mBUY_PL  >= 0.0 && mBUY_PL  >= TP_Point ) 
                || (mBuySell == OP_SELL && mSELL_PL >= 0.0 && mSELL_PL >= TP_Point ) ) {
                  // ①直前のロットがLOTSの時（= 利益が出ているときの追加取引が連続中）　→　同じ売買区分、同じロット数で継続取引

//printf( ">%d<確認" , __LINE__,mTick);


                     // ロングの場合の決済処理
                     if(mBuySell == OP_BUY) {
//printf( ">%d<確認" , __LINE__,mTick);
                     
                        if(!OrderClose(mTick,mLots, Bid,SLIPPAGE,LINE_COLOR_CLOSE)) {
                           printf( "エラーコード>%d<：：%s" , __LINE__,GetLastError());
                           ret = false;
                        } 
                     }
                     // ショートの場合の決済処理
                    
                     else if(mBuySell == OP_SELL) {
                        if(!OrderClose(mTick, mLots, Ask,SLIPPAGE,LINE_COLOR_CLOSE)) {
                           printf( "エラーコード>%d<：：%s" , __LINE__,GetLastError());
                           ret = false;
                        } 
                     }
                     else {
                        continue;
                     }
/*printf( ">%d<：：tick=>%d<の評価損益=ロング%s　　ショート%s   決済損益%s" , __LINE__,mTick, 
DoubleToStr(mBUY_PL, global_Digits), DoubleToStr(mSELL_PL, global_Digits), 
DoubleToStr(OrderProfit(), global_Digits) );*/
                    
                     //
                     // 決済処理後の継続取引の処理（１－１①直前のロットがLOTSの時）、
                     //
                     if(NormalizeDouble(mLots, global_Digits) == NormalizeDouble(LOTS, global_Digits)) { // 発注ロットがLOTSと同じなら、利益確定が続いている

                     // ADDITIONAL_TRADE_TYPE_SWITCHがfalseの場合は、直前取引と同じ売買区分の取引を新規登録。
                     // 【補足】Commentが空でないことから、直前のロットが初回取引ではない。
                     //         そのため、直前の取引ロットがLOTSの時、一連の取引は利益のみを繰り返してきたことが分かる。
                     // 　　　　直前の取引が利益を出したことで、ロット数をそのままに同じ売買区分の取引を続ける。
                     if(ADDITIONAL_TRADE_TYPE_SWITCH == false) {
                        next_BuySell = mBuySell; 
                     }
                     // ADDITIONAL_TRADE_TYPE_SWITCH == trueであれば、同じ売買区分の継続取引の見直しをする。
                     else if(ADDITIONAL_TRADE_TYPE_SWITCH == true) {
                        next_BuySell = judge_BuySell(mBuySell);  // 直前の取引が、継続取引で、利益を出したので、引数にデフォルト値として直前の取引の売買区分を渡す。
                     }
                     // 以上で、ADDITIONAL_TRADE_TYPE_SWITCHに従って、継続取引の売買区分を確定できた。
                                 
                     // 継続取引を追加する。
                     // 継続取引をロングとして発注する。
                     if(next_BuySell == OP_BUY && check_CeilingLots(mLots) == true) {
                        ticket_num = OrderSend(global_Symbol, OP_BUY,mLots, Ask, SLIPPAGE, 0.0, 0.0, nextTradeComment, MagicNumberTestCase001, LINE_COLOR_LONG);
                        if(ticket_num <= 0) {  
                           if(NormalizeDouble(mLots, global_Digits) > MarketInfo(global_Symbol,MODE_MAXLOT)) {
                              printf( "エラーコード>%d<：： 発注ロット数%sが、最大ロット数%sを超過。" , __LINE__, DoubleToStr(mLots, global_Digits), DoubleToStr(MarketInfo(global_Symbol,MODE_MAXLOT), global_Digits) );   
                           }
                           else if(AccountFreeMarginCheck(global_Symbol, OP_SELL, mLots) < 0.0) {
                              printf( "エラーコード>%d<：： 残高不足。" , __LINE__);   
                           }
                           else {
                              printf( "エラーコード>%d<：：ショート発注失敗" , __LINE__);
                           }
                           ret = false;
                        }
                     }  // 以上、if(next_BuySell == OP_BUY) {

                     // 継続取引をショートとして発注する。
                     else if(next_BuySell == OP_SELL && check_CeilingLots(mLots) == true) {
                        ticket_num = OrderSend(global_Symbol, OP_SELL, mLots, Bid, SLIPPAGE, 0.0, 0.0, nextTradeComment, MagicNumberTestCase001, LINE_COLOR_SHORT);
                        if(ticket_num <= 0) {
                           if(NormalizeDouble(mLots, global_Digits) > MarketInfo(global_Symbol,MODE_MAXLOT)) {
                              printf( "エラーコード>%d<：： 発注ロット数%sが、最大ロット数%sを超過。" , __LINE__, DoubleToStr(mLots, global_Digits), DoubleToStr(MarketInfo(global_Symbol,MODE_MAXLOT), global_Digits) );   
                           }
                           else if(AccountFreeMarginCheck(global_Symbol, OP_SELL, mLots) < 0.0) {
                              printf( "エラーコード>%d<：： 残高不足。" , __LINE__);   
                           }
                           else {
                              printf( "エラーコード>%d<：：ショート発注失敗" , __LINE__);
                           }
                           ret = false;
                        }
                     } // 以上、else if(next_BuySell == OP_SELL) {
                  }    // 以上、直前のロットがLOTSの時（= 利益が出ているときの追加取引が連続中）

                  // ②直前のロットがLOTS以外の時（= 反対売買後の利益確定）　→　継続取引はしない
                  else {
                     // 【補足説明】Commentが空でないことから、直前のロットが初回取引ではない。
                     //             そのため、直前の取引ロットがLOTS以外の時、一連の取引は損失のみを繰り返してきたことが分かる。
                     //             直前の取引が利益を出したことで、ロット数を増やして反対の売買区分で取引をする繰り返しが終わる。
                  } 
               }   // 　　以上、１ー１　決済利益が出るとき
               // １ー２　決済損失が出るとき　→　反対売買区分で、数倍したロット数で継続取引
               //         注）損失が出た場合は、『直前のロットがLOTS以外の時（= 反対売買後の利益確定）、継続取引はしない』の判断が不要のため、インデントがズレている。　
               else if( (mBuySell == OP_BUY  && mBUY_PL  < 0.0 && MathAbs(mBUY_PL)  >= SL_Point)
                     || (mBuySell == OP_SELL && mSELL_PL < 0.0 && MathAbs(mSELL_PL) >= SL_Point) ) {
//printf( ">%d<確認" , __LINE__,mTick);
                     
                  // ロングの場合の決済処理
                  if(mBuySell == OP_BUY) {
                     if(!OrderClose(mTick, mLots, Bid,SLIPPAGE,LINE_COLOR_CLOSE)) {
                        printf( "エラーコード>%d<：：%s" , __LINE__,GetLastError());
                        ret = false;
                     } 
                  }
                  // ショートの場合の決済処理
                  else if(mBuySell == OP_SELL) {
                     if(!OrderClose(mTick, mLots, Ask,SLIPPAGE,LINE_COLOR_CLOSE)) {
                        printf( "エラーコード>%d<：：%s" , __LINE__,GetLastError());
                        ret = false;
                     } 
                  }
                  else {
                     continue;
                  }
/*printf( ">%d<：：tick=>%d<の評価損益=ロング%s　　ショート%s   決済損益%s" , __LINE__,mTick, 
DoubleToStr(mBUY_PL, global_Digits), DoubleToStr(mSELL_PL, global_Digits), 
DoubleToStr(OrderProfit(), global_Digits) );*/

                  //
                  // 決済処理後（損失確定）の継続取引の処理
                  //
/*
// 決済処理した取引のロット数mLotsが、初期ロット数をMAX_ADDITIONAL_TRADE_LEVEL回掛けた場合は、
// 継続取引の処理はしない。
ceiling_Lots = MathPow(LOTS_TIMES, MAX_ADDITIONAL_TRADE_LEVEL) * LOTS;
//if(MAX_ADDITIONAL_TRADE_LEVEL == 0) {
//   ceiling_Lots = LOTS;
//}
printf( ">%d<：：LOTS=%s  MAX_ADDITIONAL_TRADE_LEVEL=%d   mLots=%s  ceiling_Lots=%s",__LINE__,
DoubleToStr(LOTS, global_Digits),
MAX_ADDITIONAL_TRADE_LEVEL,
DoubleToStr(mLots, global_Digits),
DoubleToStr(ceiling_Lots, global_Digits)
);

if(mLots > ceiling_Lots) {
printf( ">%d<：：mLots=%s が ceiling_Lots=%sを超えるため、継続取引処理はしない",__LINE__,
DoubleToStr(mLots, global_Digits),
DoubleToStr(ceiling_Lots, global_Digits)
);
   continue;
}
*/
//printf( ">%d<確認" , __LINE__,mTick);

                  // ADDITIONAL_TRADE_TYPE_SWITCHがfalseの場合は、直前取引の反対売買区分で取引を新規登録。 
                  // 【補足】直前の取引が損失を出したことで、ロット数を数倍して、逆の売買区分の取引を続ける。
                  if(ADDITIONAL_TRADE_TYPE_SWITCH == false) {
                     if(mBuySell == OP_BUY) {
                        next_BuySell = OP_SELL;
                     }
                     else {
                        next_BuySell = OP_BUY;
                     }
                  }
                  // ADDITIONAL_TRADE_TYPE_SWITCH == trueであれば、継続取引の見直しをする。
                  else if(ADDITIONAL_TRADE_TYPE_SWITCH == true) {
                     revBuySell = NO_SIGNAL;
                     if(mBuySell == OP_BUY) {
                        revBuySell = OP_SELL;
                     }
                     else {
                        revBuySell = OP_BUY;
                     }
                     next_BuySell = judge_BuySell(revBuySell); // 直前の取引が、継続取引で、損失を出したので、引数にデフォルト値として直前の取引の反対売買区分を渡す。
                  }
//printf( ">%d<確認" , __LINE__,mTick);

                         
                  // 以上で、ADDITIONAL_TRADE_TYPE_SWITCHに従って、継続取引の売買区分を確定できた。
                  // 継続取引を追加する。
                  // 継続取引をロングとして発注する。
                  if(next_BuySell == OP_BUY && check_CeilingLots(mLots * LOTS_TIMES) == true) {
                     ticket_num = OrderSend(global_Symbol, OP_BUY,mLots * LOTS_TIMES, Ask, SLIPPAGE, 0.0, 0.0, nextTradeComment, MagicNumberTestCase001, LINE_COLOR_LONG);
//printf( ">%d<：：tick=>%d<で損失が出たため、継続取引ロングを発注。tick=%d ロット数は>%s<　コメントは>%s<" , __LINE__,mTick, ticket_num, DoubleToStr(mLots * LOTS_TIMES, global_Digits), nextTradeComment);                           
                        if(ticket_num <= 0) {  
                           if(NormalizeDouble(mLots * LOTS_TIMES, global_Digits) > MarketInfo(global_Symbol,MODE_MAXLOT)) {
                              printf( "エラーコード>%d<：： 発注ロット数%sが、最大ロット数%sを超過。" , __LINE__, DoubleToStr(mLots * LOTS_TIMES, global_Digits), DoubleToStr(MarketInfo(global_Symbol,MODE_MAXLOT), global_Digits) );   
                           }
                           else if(AccountFreeMarginCheck(global_Symbol, OP_SELL, mLots * LOTS_TIMES) < 0.0) {
                              printf( "エラーコード>%d<：： 残高不足。" , __LINE__);   
                           }
                           else {
                              printf( "エラーコード>%d<：：ショート発注失敗" , __LINE__);
                           }
                           ret = false;
                        }
                  }   // 以上、if(next_BuySell == OP_BUY) {

                  // 継続取引をショートとして発注する。
                  else if(next_BuySell == OP_SELL && check_CeilingLots(mLots * LOTS_TIMES) == true) {
//printf( ">%d<確認" , __LINE__,mTick);
                  
                     ticket_num = OrderSend(global_Symbol, OP_SELL,mLots * LOTS_TIMES, Bid, SLIPPAGE, 0.0, 0.0, nextTradeComment, MagicNumberTestCase001, LINE_COLOR_SHORT);
//printf( ">%d<：：ロング　tick=>%d<で損失が出たので、ショートを実施。継続取引のtick=%d　　ロットは%s" , __LINE__,mTick, ticket_num, DoubleToStr(mLots * LOTS_TIMES, global_Digits)); 
                        if(ticket_num <= 0) {  
                           if(NormalizeDouble(mLots * LOTS_TIMES, global_Digits) > MarketInfo(global_Symbol,MODE_MAXLOT)) {
                              printf( "エラーコード>%d<：： 発注ロット数%sが、最大ロット数%sを超過。" , __LINE__, DoubleToStr(mLots * LOTS_TIMES, global_Digits), DoubleToStr(MarketInfo(global_Symbol,MODE_MAXLOT), global_Digits) );   
                           }
                           else if(AccountFreeMarginCheck(global_Symbol, OP_SELL, mLots * LOTS_TIMES) < 0.0) {
                              printf( "エラーコード>%d<：： 残高不足。" , __LINE__);   
                           }
                           else {
                              printf( "エラーコード>%d<：：ショート発注失敗" , __LINE__);
                           }
                           ret = false;
                        }
                  }
               }  // 以上、１ー２　決済損失が出るとき　→　反対売買区分で、数倍したロット数で継続取引　　　
            }     // 以上、１　直前のCommentが空以外＝初回取引ではない

            // ２　直前のCommentが空（直前取引が、初回取引）
            // 　　２ー１　決済利益が出るとき　→　同じ売買区分、同じロット数で継続取引
            // 　　２ー２　決済損失が出るとき　→　反対売買区分で、数倍したロット数で継続取引
            else {
               // ２ー１　決済利益が出るとき　→　同じ売買区分、同じロット数で継続取引＝初回取引が利益を出したときの継続取引
               if( (mBuySell == OP_BUY  && mBUY_PL  >= 0.0 && mBUY_PL >= TP_Point)
                || (mBuySell == OP_SELL && mSELL_PL >= 0.0 && mSELL_PL >= TP_Point) ) {
                  // 直前の取引が存在しないため、取引の売買区分に応じて、決済する。
                  // ロングの場合の決済処理
                  if(mBuySell == OP_BUY) {
                     if(!OrderClose(mTick, mLots, Bid,SLIPPAGE,LINE_COLOR_CLOSE)) {
                        printf( "エラーコード>%d<：：%s" , __LINE__,GetLastError());
                        ret = false;
                     } 
                  }
                  // ショートの場合の決済処理
                  else if(mBuySell == OP_SELL) {
                     if(!OrderClose(mTick, mLots, Ask,SLIPPAGE,LINE_COLOR_CLOSE)) {
                        printf( "エラーコード>%d<：：%s" , __LINE__,GetLastError());
                        ret = false;
                     } 
                  }
                  else {
                     continue;
                  }
/*printf( ">%d<：：tick=>%d<の評価損益=ロング%s　　ショート%s   決済損益%s" , __LINE__,mTick, 
DoubleToStr(mBUY_PL, global_Digits), DoubleToStr(mSELL_PL, global_Digits), 
DoubleToStr(OrderProfit(), global_Digits) );*/
                  
/*                  
// 決済処理した取引のロット数mLotsが、初期ロット数をMAX_ADDITIONAL_TRADE_LEVEL回掛けた場合は、
// 継続取引の処理はしない。
ceiling_Lots = MathPow(LOTS_TIMES, MAX_ADDITIONAL_TRADE_LEVEL) * LOTS;
//if(MAX_ADDITIONAL_TRADE_LEVEL == 0) {
//   ceiling_Lots = LOTS;
//}
printf( ">%d<：：LOTS=%s  MAX_ADDITIONAL_TRADE_LEVEL=%d   mLots=%s  ceiling_Lots=%s",__LINE__,
DoubleToStr(LOTS, global_Digits),
MAX_ADDITIONAL_TRADE_LEVEL,
DoubleToStr(mLots, global_Digits),
DoubleToStr(ceiling_Lots, global_Digits)
);

if(mLots > ceiling_Lots) {
printf( ">%d<：：mLots=%s が ceiling_Lots=%sを超えるため、継続取引処理はしない",__LINE__,
DoubleToStr(mLots, global_Digits),
DoubleToStr(ceiling_Lots, global_Digits)
);
   continue;
} 
*/        

                  // ADDITIONAL_TRADE_TYPE_SWITCHがfalseの場合は、直前取引と同じ取引を新規登録。
                  // 【補足】Commentが空であるから、直前の取引は初回取引限定。
                  //         そのため、利益が出ていれば、ロット数はそのままで同じ売買区分で継続取引する。
                  if(ADDITIONAL_TRADE_TYPE_SWITCH == false) {
                     next_BuySell = mBuySell; // 直前の取引がロングの場合は
                  }
                  // ADDITIONAL_TRADE_TYPE_SWITCH == trueであれば、継続取引の見直しをする。
                  else if(ADDITIONAL_TRADE_TYPE_SWITCH == true) {
                     next_BuySell = judge_BuySell(mBuySell);  // 直前の取引が、継続取引で、利益を出したので、引数にデフォルト値として直前の取引の売買区分を渡す。
                  }     
                  // 以上で、ADDITIONAL_TRADE_TYPE_SWITCHに従って、継続取引の売買区分を確定できた。

                  // 継続取引を追加する。
                  // 継続取引をロングとして発注する。
                  if(next_BuySell == OP_BUY && check_CeilingLots(mLots) == true) {
                  
                     ticket_num = OrderSend(global_Symbol, OP_BUY,mLots, Ask, SLIPPAGE, 0.0, 0.0, nextTradeComment, MagicNumberTestCase001, LINE_COLOR_LONG);
//printf( ">%d<：：tick=>%d<と同じロングを実施。継続取引のtick=%d ロット数は>%s<　コメントは>%s<" , __LINE__,mTick, ticket_num, DoubleToStr(mLots, global_Digits), nextTradeComment);                           
                     if(ticket_num <= 0) {  
                        if(NormalizeDouble(mLots, global_Digits) > MarketInfo(global_Symbol,MODE_MAXLOT)) {
                           printf( "エラーコード>%d<：： 発注ロット数%sが、最大ロット数%sを超過。" , __LINE__, DoubleToStr(mLots, global_Digits), DoubleToStr(MarketInfo(global_Symbol,MODE_MAXLOT), global_Digits) );   
                        }
                        else if(AccountFreeMarginCheck(global_Symbol, OP_SELL, mLots) < 0.0) {
                           printf( "エラーコード>%d<：： 残高不足。" , __LINE__);   
                        }
                        else {
                           printf( "エラーコード>%d<：：ショート発注失敗" , __LINE__);
                        }
                        ret = false;
                     }
                  }  // 以上、if(next_BuySell == OP_BUY) {

                  // 継続取引をショートとして発注する。
                  else if(next_BuySell == OP_SELL && check_CeilingLots(mLots) == true) {
//printf( ">%d<：：tick=>%d<と同じショートを実施。継続取引のtick=%d ロット数は>%s<　コメントは>%s<" , __LINE__,mTick, ticket_num);                                                      
                     ticket_num = OrderSend(global_Symbol, OP_SELL,mLots, Bid, SLIPPAGE, 0.0, 0.0, nextTradeComment, MagicNumberTestCase001, LINE_COLOR_SHORT);
                        if(ticket_num <= 0) {  
                           if(NormalizeDouble(mLots, global_Digits) > MarketInfo(global_Symbol,MODE_MAXLOT)) {
                              printf( "エラーコード>%d<：： 発注ロット数%sが、最大ロット数%sを超過。" , __LINE__, DoubleToStr(mLots, global_Digits), DoubleToStr(MarketInfo(global_Symbol,MODE_MAXLOT), global_Digits) );   
                           }
                           else if(AccountFreeMarginCheck(global_Symbol, OP_SELL, mLots) < 0.0) {
                              printf( "エラーコード>%d<：： 残高不足。" , __LINE__);   
                           }
                           else {
                              printf( "エラーコード>%d<：：ショート発注失敗" , __LINE__);
                           }
                           ret = false;
                        }
                  } // 以上、else if(next_BuySell == OP_SELL) {
               }    // 以上、２　直前のCommentが空　→　２ー１　決済利益が出るとき
               // ２ー２　決済損失が出るとき　→　反対売買区分で、数倍したロット数で継続取引
               else if( (mBuySell == OP_BUY && mBUY_PL   < 0.0 && MathAbs(mBUY_PL) >= SL_Point)
                     || (mBuySell == OP_SELL && mSELL_PL < 0.0 && MathAbs(mSELL_PL) >= SL_Point) ){
                  // ロングの場合の決済処理
                  if(mBuySell == OP_BUY) {
                     if(!OrderClose(mTick, mLots, Bid,SLIPPAGE,LINE_COLOR_CLOSE)) {
                        printf( "エラーコード>%d<：：%s" , __LINE__,GetLastError());
//printf( ">%d<：：ロング　tick=>%d<の決済失敗" , __LINE__,mTick);
                        ret = false;
                     } 
                  }
                  // ショートの場合の決済処理
                  else if(mBuySell == OP_SELL) {
                     if(!OrderClose(mTick, mLots, Ask,SLIPPAGE,LINE_COLOR_CLOSE)) {
                        printf( "エラーコード>%d<：：%s" , __LINE__,GetLastError());
//printf( ">%d<：：ショート　tick=>%d<の決済失敗" , __LINE__,mTick);
                        ret = false;
                     } 
                  }
/*printf( ">%d<：：tick=>%d<の評価損益=ロング%s　　ショート%s   決済損益%s" , __LINE__,mTick, 
DoubleToStr(mBUY_PL, global_Digits), DoubleToStr(mSELL_PL, global_Digits), 
DoubleToStr(OrderProfit(), global_Digits) );*/

/*
// 決済処理した取引のロット数mLotsが、初期ロット数をMAX_ADDITIONAL_TRADE_LEVEL回掛けた場合は、
// 継続取引の処理はしない。
ceiling_Lots = MathPow(LOTS_TIMES, MAX_ADDITIONAL_TRADE_LEVEL) * LOTS;
//if(MAX_ADDITIONAL_TRADE_LEVEL == 0) {
//   ceiling_Lots = LOTS;
//}
printf( ">%d<：：LOTS=%s  MAX_ADDITIONAL_TRADE_LEVEL=%d   mLots=%s  ceiling_Lots=%s",__LINE__,
DoubleToStr(LOTS, global_Digits),
MAX_ADDITIONAL_TRADE_LEVEL,
DoubleToStr(mLots, global_Digits),
DoubleToStr(ceiling_Lots, global_Digits)
);

if(mLots > ceiling_Lots) {
printf( ">%d<：：mLots=%s が ceiling_Lots=%sを超えるため、継続取引処理はしない",__LINE__,
DoubleToStr(mLots, global_Digits),
DoubleToStr(ceiling_Lots, global_Digits)
);
   continue;
}
*/
                //
                  // 決済処理後の継続取引の処理
                  //


                  // ADDITIONAL_TRADE_TYPE_SWITCHがfalseの場合は、直前取引の反対売買区分で取引を新規登録。                     
                  // 【補足】Commentが空であるから、直前の取引は初回取引限定。
                  //         そのため、損失であれば、ロット数は数倍して、逆の売買区分で継続取引する。
                  if(ADDITIONAL_TRADE_TYPE_SWITCH == false) {
                     if(mBuySell == OP_BUY) {
                        next_BuySell = OP_SELL;
                     }
                     else {
                        next_BuySell = OP_BUY;
                     }
                  }
                  // ADDITIONAL_TRADE_TYPE_SWITCH == trueであれば、継続取引の見直しをする。
                  else if(ADDITIONAL_TRADE_TYPE_SWITCH == true) {
                     revBuySell = NO_SIGNAL;
                     if(mBuySell == OP_BUY) {
                        revBuySell = OP_SELL;
                     }
                     else {
                        revBuySell = OP_BUY;
                     }
                     next_BuySell = judge_BuySell(revBuySell); // 直前の取引が、継続取引で、損失が出したので、引数にデフォルト値として直前の取引の反対売買区分を渡す。
                  }
                            
                  // 以上で、ADDITIONAL_TRADE_TYPE_SWITCHに従って、継続取引の売買区分を確定できた。
                  // 継続取引を追加する。
                  // 継続取引をロングとして発注する。
                  if(next_BuySell == OP_BUY && check_CeilingLots(mLots * LOTS_TIMES) == true) {
                  
                     ticket_num = OrderSend(global_Symbol, OP_BUY,mLots * LOTS_TIMES, Ask, SLIPPAGE, 0.0, 0.0, nextTradeComment, MagicNumberTestCase001, LINE_COLOR_LONG);
//printf( ">%d<：：tick=>%d<で損失が出たため、継続取引ロングを発注。tick=%d ロット数は>%s<　コメントは>%s<" , __LINE__,mTick, ticket_num, DoubleToStr(mLots * LOTS_TIMES, global_Digits), nextTradeComment);                           
                     if(ticket_num <= 0) {  
                        if(NormalizeDouble(mLots * LOTS_TIMES, global_Digits) > MarketInfo(global_Symbol,MODE_MAXLOT)) {
                           printf( "エラーコード>%d<：： 発注ロット数%sが、最大ロット数%sを超過。" , __LINE__, DoubleToStr(mLots * LOTS_TIMES, global_Digits), DoubleToStr(MarketInfo(global_Symbol,MODE_MAXLOT), global_Digits) );   
                        }
                        else if(AccountFreeMarginCheck(global_Symbol, OP_SELL, mLots * LOTS_TIMES) < 0.0) {
                           printf( "エラーコード>%d<：： 残高不足。" , __LINE__);   
                        }
                        else {
                           printf( "エラーコード>%d<：：ショート発注失敗" , __LINE__);
                        }
                        ret = false;
                     }  // 以上、if(next_BuySell == OP_BUY) {
                  }
                  // 継続取引をショートとして発注する。
                  else if(next_BuySell == OP_SELL && check_CeilingLots(mLots * LOTS_TIMES) == true) {
                  
                     ticket_num = OrderSend(global_Symbol, OP_SELL,mLots * LOTS_TIMES, Bid, SLIPPAGE, 0.0, 0.0, nextTradeComment, MagicNumberTestCase001, LINE_COLOR_SHORT);
//printf( ">%d<：：ロング　tick=>%d<で損失が出たので、ショートを実施。継続取引のtick=%d　　ロットは%s コメントは>%s<" , __LINE__,mTick, ticket_num, DoubleToStr(mLots * LOTS_TIMES, global_Digits), nextTradeComment); 
                     if(ticket_num <= 0) {  
                        if(NormalizeDouble(mLots * LOTS_TIMES, global_Digits) > MarketInfo(global_Symbol,MODE_MAXLOT)) {
                           printf( "エラーコード>%d<：： 発注ロット数%sが、最大ロット数%sを超過。" , __LINE__, DoubleToStr(mLots * LOTS_TIMES, global_Digits), DoubleToStr(MarketInfo(global_Symbol,MODE_MAXLOT), global_Digits) );   
                        }
                        else if(AccountFreeMarginCheck(global_Symbol, OP_SELL, mLots * LOTS_TIMES) < 0.0) {
                           printf( "エラーコード>%d<：： 残高不足。" , __LINE__);   
                        }
                        else {
                           printf( "エラーコード>%d<：：ショート発注失敗" , __LINE__);
                        }
                        ret = false;
                     } 
                  }
               }  // 以上、２ー２　決済損失が出るとき　→　反対売買区分で、数倍したロット数で継続取引
            }
         }
      }
   }
//printf( ">%d<確認" , __LINE__);
   
   return ret;
}

bool check_CeilingLots(double mLots) {
   double ceiling_Lots = MathPow(LOTS_TIMES, MAX_ADDITIONAL_TRADE_LEVEL) * LOTS;

/*   printf( ">%d<：：LOTS=%s  MAX_ADDITIONAL_TRADE_LEVEL=%d   mLots=%s  ceiling_Lots=%s",__LINE__,
   DoubleToStr(LOTS, global_Digits),
   MAX_ADDITIONAL_TRADE_LEVEL,
   DoubleToStr(mLots, global_Digits),
   DoubleToStr(ceiling_Lots, global_Digits)
   );*/
   
   if(mLots > ceiling_Lots) {
      printf( ">%d<：：mLots=%s が ceiling_Lots=%sを超えるため、継続取引処理はしない",__LINE__,
      DoubleToStr(mLots, global_Digits),
      DoubleToStr(ceiling_Lots, global_Digits)
      );
      return false;
   }
   
   return true;
}


//printf( ">%d<　　チケット=%d 約定日=%s ロット=%s  コメント=%s" , __LINE__, OrderTicket(), TimeToStr(OrderOpenTime()), DoubleToStr(OrderLots()), OrderComment());
// 引数のマジックナンバーを持ち、初回取引（Commentが空欄）で、未決済な取引件数を返す。
bool is_OriginalTradeOpen(long mMagic,
                          long &mOriginal_Trade_Tick[]
                          ) {
   Original_Trade_Num = 0;
   int originalTradeTick = -1;
   int i;
   int j;

/*
   for(i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
        printf( ">%d<：：is_OriginalTradeOpenの処理対象全件マジック>%d< チケット>%d< コメント>%s<" , __LINE__,
               OrderMagicNumber(),
               OrderTicket(), 
               OrderComment()
               );
     }
  }
*/


   for(i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
         if(OrderMagicNumber() == mMagic){                // マジックナンバー
         
            // if(StringCompare(OrderComment(), "") != 0) {  // コメントに何らかの文字あり
            if(StringLen(OrderComment()) > 0) {
            
               if(OrderCloseTime() <= 0) {                  // 決済前
                  string sep_str[];
                  int    sep_num;
                  long   tickInComment = 0;
                  sep_num = StringSplit(OrderComment() , ',' , sep_str);
                  tickInComment = StringToInteger(sep_str[1]);

                  // Original_Trade_Tick[9999]の中にtickInCommentがあれば、オープンな継続取引が存在しているため、trueを返す。
                  for(j = 0; j < 9999; j++) {
                     if(mOriginal_Trade_Tick[j] <= 0) {
                        break;
                     }
/*
printf( ">%d<：：コメント=%s　→　>%s< + >%s< + >%s< Original_Trade_Tick[%d]=%d" , __LINE__,
OrderComment(),
sep_str[0],
sep_str[1],
sep_str[2],
j,
Original_Trade_Tick[j]
);
*/
                     if(tickInComment == Original_Trade_Tick[j]) {
                        return true;
                     }
                  }
               }
            }
            // else if(StringCompare(OrderComment(), "") == 0) {  // コメント空欄で初期取引
            else if(StringLen(OrderComment()) == 0) {
               if(OrderCloseTime() <= 0) {                  // 決済前
               
                  return true;            
               }
            }
         } 
      }
   }
   
   return false;
}


int get_OriginalTradeTick(long mMagic,                 // マジックナンバー
                          long &mOriginal_Trade_Tick[] // 出力：オリジナル取引のチケット番号一覧
                          ) {
   int i;                          
/*
   for(i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
         printf( ">%d<：：get_OriginalTradeTickの対象全件＊＊＊マジック>%d< チケット>%d< コメント>%s<" , __LINE__,
               OrderMagicNumber(),
               OrderTicket(), 
               OrderComment()
               );      
     }
  }
*/


   ArrayInitialize(Original_Trade_Tick, 0);

 //  int doneOriginalTradeTick[9999];
 //  int doneOriginalTradeNum=0;
 //  ArrayInitialize(doneOriginalTradeTick, 0);
   
   int count = 0;
   // 未決済のオリジナル取引の件数
   for(i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
         if(OrderMagicNumber() == mMagic){
         
            // オリジナル取引で未決済の場合
            // if(StringCompare(OrderComment(), "") == 0) {  
            if(StringLen(OrderComment()) == 0) {  
               if(OrderCloseTime() <= 0) {
                  mOriginal_Trade_Tick[count] = OrderTicket();
                  count++;
               }
            }
            // 継続取引の要件を満たしていれば、コメントからチケット番号を抽出して配列に保存
            // 継続取引の要件は、コメントが３要素を持ち、順に、正の整数（マジックナンバー）、正の整数（チケット）、正の数（ロット）とする。
            // else if(StringCompare(OrderComment(), "") == 0) {  
            else if(StringLen(OrderComment()) > 0) {
            
               string sep_str[];
               int    sep_num;
               long    magicInComment = 0;
               long   tickInComment  = 0;
               double lotsInComment  = 0.0;
               sep_num = StringSplit(OrderComment() , ',' , sep_str);
               magicInComment = StringToInteger(sep_str[0]);
               tickInComment  = StringToInteger(sep_str[1]);
               lotsInComment  = StringToDouble(sep_str[2]);
         
               if(sep_num == 3 && magicInComment > 0 && tickInComment > 0 && lotsInComment > 0.0) {
                  mOriginal_Trade_Tick[count] = tickInComment;
                  count++;                  
               }
            }
         }
      }
   }
   
   /*
   // 決済済みのオリジナル取引の継続取引のうち、未決済んお件数
   for(i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
         if(OrderMagicNumber() == mMagic){
            if(StringCompare(OrderComment(), "") != 0) {  
               //　継続取引候補
               if(OrderCloseTime() <= 0) {

                  mOriginal_Trade_Tick[count] = OrderTicket();
                  count++;
               }
               // オリジナル取引は決済されていたが、継続取引がオープンかどうかを調べるため、チケット番号を配列に保存
               else {
                  doneOriginalTradeTick[doneOriginalTradeNum] = OrderTicket();
                  doneOriginalTradeNum++;
               }
            }
         }
      }
   }   
   */
   return count;
}



// １，とりあえず任意のタイミングで１単位ロング（またはショート）（利確も損切りも３ｐｉｐｓ）
// 【注意】実際には、利用するFX業者によりストップレベルが異なるため、3PIPSという狭い範囲で利確、損切設定は不可能。
//         そのため、関数で利確、損切を行う。
int mOrderSend_OriginalTrade(int mMagic) {
   int flag_judge_BuySell = -1;
   int orderNum = OrdersHistoryTotal();
   
   // 取引できるかどうかを判断する。
   bool flag_judge_Tradable = judge_Tradable(2);  // 取引可能な場合はtrue。不可能な場合はfalse。// 1:スプレッドのみ。2：スプレッドとレバレッジ
   if(flag_judge_Tradable == false) {
      return ERROR_ORDERSEND;
   }

   // 発注判断
   flag_judge_BuySell = judge_BuySell(NO_SIGNAL);
   int ticket_num = -1;

   // ロングをする際
   if(flag_judge_BuySell == OP_BUY) {
      ticket_num = OrderSend(global_Symbol, OP_BUY, LOTS, Ask, SLIPPAGE, 0.0, 0.0, "", MagicNumberTestCase001, LINE_COLOR_LONG);
      if(ticket_num <= 0) {  
         if(NormalizeDouble(LOTS, global_Digits) > MarketInfo(global_Symbol,MODE_MAXLOT)) {
            printf( "エラーコード>%d<：： 発注ロット数%sが、最大ロット数%sを超過。" , __LINE__, DoubleToStr(LOTS, global_Digits), DoubleToStr(MarketInfo(global_Symbol,MODE_MAXLOT), global_Digits) );   
         }
         else if(AccountFreeMarginCheck(global_Symbol, OP_SELL, LOTS) < 0.0) {
            printf( "エラーコード>%d<：： 残高不足。" , __LINE__);   
         }
         else {
            printf( "エラーコード>%d<：：ショート発注失敗" , __LINE__);
         }
         return ERROR_ORDERSEND;
      }      
   }

   // ショートをする際
   if(flag_judge_BuySell == OP_SELL) {
      ticket_num = OrderSend(global_Symbol, OP_SELL, LOTS, Bid, SLIPPAGE, 0.0, 0.0,"", MagicNumberTestCase001, LINE_COLOR_SHORT);
      if(ticket_num <= 0) {  
         if(NormalizeDouble(LOTS, global_Digits) > MarketInfo(global_Symbol,MODE_MAXLOT)) {
            printf( "エラーコード>%d<：： 発注ロット数%sが、最大ロット数%sを超過。" , __LINE__, DoubleToStr(LOTS, global_Digits), DoubleToStr(MarketInfo(global_Symbol,MODE_MAXLOT), global_Digits) );   
         }
         else if(AccountFreeMarginCheck(global_Symbol, OP_SELL, LOTS) < 0.0) {
            printf( "エラーコード>%d<：： 残高不足。" , __LINE__);   
         }
         else {
            printf( "エラーコード>%d<：：ショート発注失敗" , __LINE__);
         }
         return ERROR_ORDERSEND;
      }
   }
   return ticket_num;
}

	
// ロングかショートを判断する。
// 引数：なし。
// 返り値：OP_BUY又はOP_SELL、いずれでもない場合は-1
// 
// 【参考】BUYSELL_TYPE_JUDGE_METHODは、-2～8を取りうる。
//  -2:ショートのみ。-1:ロングのみ。0:ロング、ショートいづれも無し
//  1:4時間足のトレンド利用 2:上記1に加え、長短期移動平均利用   3:上記2に加え、長短期移動平均線が直前に交差
//  4:ランダム           5:ボリンジャーバンド（±3σ）利用―順張り  6:ボリンジャーバンド（±3σ）利用逆順張り 
//  7:ボリンジャーバンドとボラティリティを使った順張り＋逆張り          8:ローソクのヒゲ利用

/*
int judge_BuySell() {
   int  trendEMA   = NoTrend; // UpTrend, DownTrend, NoTrendのいずれか。
   int  trendCross = NoTrend; // UpTrend, DownTrend, NoTrendのいずれか。
   bool Crossflag  = false;   // ゴールデンクロス又はデッドクロスが発生していれば、true

   int condition1 = -1;
   int condition2 = -1;
   int condition3 = -1;
   int condition4 = -1;
   int condition5 = -1;
   int condition6 = -1;
   int condition7 = -1;   

   // 条件1：EMAが上向きであればロング、下向きであればショート
   trendEMA = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸(PERIOD_H4以下は、4時間足を使う）
                                     1   // 何シフト前から判断するか
                                     ); 
   if(trendEMA == UpTrend) {
      condition1 = OP_BUY;
   }
   else if(trendEMA == DownTrend) {
      condition1 = OP_SELL;
   }
   else {
      condition1 = NO_SIGNAL;
   }

   // 条件2：移動平均MAの短期が長期の上にあれば、ロング。反対ならショート
   trendCross = get_MAGCDC(0,        // 判断に使う時間軸 
                           1,        // 何シフト前から判断するか
                           Crossflag // クロスした直後ならtrue
                           ); 
   if(trendCross == UpTrend) {
      condition2 = OP_BUY;
   }
   else if(trendCross == DownTrend) {
      condition2 = OP_SELL;
   }
   else {
      condition2 = NO_SIGNAL;
   }

   // 条件3：移動平均MAの短期が長期の上にあれば、ロング。反対ならショート。ただし、クロスした直後であること。
   trendCross = get_MAGCDC(0,        // 判断に使う時間軸 
                           1,        // 何シフト前から判断するか
                           Crossflag // クロスした直後ならtrue
                           ); 
   if(trendCross == UpTrend && Crossflag == true) {
      condition3 = OP_BUY;
   }
   else if(trendCross == DownTrend && Crossflag == true) {
      condition3 = OP_SELL;
   }
   else {
      condition3 = NO_SIGNAL;
   }

   // 条件4：ランダム取引の条件を使う
   int flagRT = entryRT_only_Rand();
   RTMethod = 0;
   if(flagRT == OP_BUY) {
      condition4 = OP_BUY;
   }   
   else if(flagRT == OP_SELL) {
      condition4 = OP_SELL;
   }
   else {
      condition4 = NO_SIGNAL;
   }
   
   // 条件5：ボリンジャーバンドの条件を使う
   int flagBB = entryBB();
   if(flagBB == OP_BUY) {
      condition5 = OP_BUY;
   }   
   else if(flagBB == OP_SELL) {
      condition5 = OP_SELL;
   }
   else {
      condition5 = NO_SIGNAL;
   }

   // 条件6：ボリンジャーバンド及びボラティリティの条件を使う
   int flagRVI = entryRVI();
   if(flagBB == OP_BUY) {
      condition6 = OP_BUY;
   }   
   else if(flagRVI == OP_SELL) {
      condition6 = OP_SELL;
   }
   else {
      condition6 = NO_SIGNAL;
   }


   // 条件6：PinBarの条件を使う
   int flagPinBar = entryPinBar();
   PinBarMethod = 7;
   if(flagPinBar == OP_BUY) {
      condition7 = OP_BUY;
   }   
   else if(flagPinBar == OP_SELL) {
      condition7 = OP_SELL;
   }
   else {
      condition7 = NO_SIGNAL;
   }

   int retValue;
   // -2:ショート
   if(BUYSELL_TYPE_JUDGE_METHOD == -2) {
      retValue = OP_SELL;
   }

   // -1:ロング
   if(BUYSELL_TYPE_JUDGE_METHOD == -1) {
      retValue = OP_BUY;
   }

   // 0:シグナルなし
   if(BUYSELL_TYPE_JUDGE_METHOD == 0) {
      retValue = NO_SIGNAL;
   }

   // 1:4時間足のトレンド利用
   if(BUYSELL_TYPE_JUDGE_METHOD == 1) {
      retValue = condition1;
   }
   // 2:4時間足のトレンドと長短期移動平均利用
   else if(BUYSELL_TYPE_JUDGE_METHOD == 2) {
      if(condition1 == OP_BUY && condition2 == OP_BUY) {
         retValue = OP_BUY;
      }
      else if(condition1 == OP_SELL && condition2 == OP_SELL) {
         retValue = OP_SELL;
      }
      else {
         retValue = -1;
      }
   }
   // 4時間足のトレンドと長短期移動平均、クロス発生状況を利用
   else if(BUYSELL_TYPE_JUDGE_METHOD == 3) {  
      if(condition1 == OP_BUY && condition3 == OP_BUY) {
         retValue = OP_BUY;
      }
      else if(condition1 == OP_SELL && condition3 == OP_SELL) {
         retValue = OP_SELL;
      }
      else {
         retValue = NO_SIGNAL;
      }
   }

   // ランダム
   else if(BUYSELL_TYPE_JUDGE_METHOD == 4) {
      retValue = condition4;      
   }

   // ボリンジャーバンドentryBB()利用
   else if(BUYSELL_TYPE_JUDGE_METHOD == 5) {
      retValue = condition5;
   }

   // ボリンジャーバンド&ボラティリティ利用
   else if(BUYSELL_TYPE_JUDGE_METHOD == 5) {
      retValue = condition6;
   }

   // ヒゲの活用
   else if(BUYSELL_TYPE_JUDGE_METHOD == 6) {
      retValue = condition7;
   }

   else {
      retValue = NO_SIGNAL;
   }

   return retValue;
}
*/


// １，とりあえず任意のタイミングで１単位ロング（またはショート）（利確も損切りも３ｐｉｐｓ）
// 【注意】実際には、利用するFX業者によりストップレベルが異なるため、3PIPSという狭い範囲で利確、損切設定は不可能。
//         そのため、関数で利確、損切を行う。
/*
int judge_BuySell(int mMagic, 
               int mDefault // 売買区分が、売りでも買いでもないときのデフォルト値
) {
   int flag_judge_BuySell = -1;
   int orderNum = OrdersHistoryTotal();
 
   // 取引できるかどうかを判断する。
   bool flag_judge_Tradable = judge_Tradable(1);  // 取引可能な場合はtrue。不可能な場合はfalse。// 1:スプレッドのみ。2：スプレッドとレバレッジ
   if(flag_judge_Tradable == false) {
      return ERROR_ORDERSEND;
   }

   // 発注判断
   flag_judge_BuySell = judge_BuySell(NO_SIGNAL);
   int ticket_num = -1;;

   // ロングをする際
   if(flag_judge_BuySell == OP_BUY) {
      ticket_num = OrderSend(global_Symbol, OP_BUY, LOTS, Ask, SLIPPAGE, 0.0, 0.0, "", MagicNumberTestCase001, LINE_COLOR_LONG);
      if(ticket_num <= 0) {  
         if(NormalizeDouble(LOTS, global_Digits) > MarketInfo(global_Symbol,MODE_MAXLOT)) {
            printf( "エラーコード>%d<：： 発注ロット数%sが、最大ロット数%sを超過。" , __LINE__, DoubleToStr(LOTS, global_Digits), DoubleToStr(MarketInfo(global_Symbol,MODE_MAXLOT), global_Digits) );   
         }
         else if(AccountFreeMarginCheck(global_Symbol, OP_SELL, LOTS) < 0.0) {
            printf( "エラーコード>%d<：： 残高不足。" , __LINE__);   
         }
         else {
            printf( "エラーコード>%d<：：ショート発注失敗" , __LINE__);
         }
         return ERROR_ORDERSEND;
      }      
   }

   // ショートをする際
   else if(flag_judge_BuySell == OP_SELL) {
      ticket_num = OrderSend(global_Symbol, OP_SELL, LOTS, Bid, SLIPPAGE, 0.0, 0.0,"", MagicNumberTestCase001, LINE_COLOR_SHORT);
      if(ticket_num <= 0) {  
         if(NormalizeDouble(LOTS, global_Digits) > MarketInfo(global_Symbol,MODE_MAXLOT)) {
            printf( "エラーコード>%d<：： 発注ロット数%sが、最大ロット数%sを超過。" , __LINE__, DoubleToStr(LOTS, global_Digits), DoubleToStr(MarketInfo(global_Symbol,MODE_MAXLOT), global_Digits) );   
         }
         else if(AccountFreeMarginCheck(global_Symbol, OP_SELL, LOTS) < 0.0) {
            printf( "エラーコード>%d<：： 残高不足。" , __LINE__);   
         }
         else {
            printf( "エラーコード>%d<：：ショート発注失敗" , __LINE__);
         }
         return ERROR_ORDERSEND;
      }      
   }
   return ticket_num;
}
*/

// ロングかショートを判断する。
// ロング、ショートを判断できない場合は、引数のmDeflautを返すバージョン
// 例えば、損失発生時に単純な反対売買“以外”を発注する際に使用する。
// 引数：ロング、ショートを判断できない場合は、引数のmDeflautを返す
// 返り値：OP_BUY又はOP_SELL、引数で渡した値
int judge_BuySell(int mDefault) {  
   int  trendEMA   = NoTrend; // UpTrend, DownTrend, NoTrendのいずれか。
   int  trendCross = NoTrend; // UpTrend, DownTrend, NoTrendのいずれか。
   bool Crossflag  = false;   // 

   int condition1 = -1;
   int condition2 = -1;
   int condition3 = -1;
   int condition4 = -1;
   int condition5 = -1;
   int condition6 = -1;
   int condition7 = -1;   
   int condition8 = -1;   
   
   // 条件1：EMAが上向きであればロング、下向きであればショート
   trendEMA = get_Trend_EMA_PERIODH4(0,  // 判断に使う時間軸(PERIOD_H4以下は、4時間足を使う）
                                     1   // 何シフト前から判断するか
                                     ); 
   if(trendEMA == UpTrend) {
      condition1 = OP_BUY;
   }
   else if(trendEMA == DownTrend) {
      condition1 = OP_SELL;
   }
   else {
      condition1 = mDefault;
   }

   // 条件2：移動平均MAの短期が長期の上にあれば、ロング。反対ならショート
   trendCross = get_MAGCDC(0,        // 判断に使う時間軸 
                           1,        // 何シフト前から判断するか
                           Crossflag // クロスした直後ならtrue
                           ); 
   if(trendCross == UpTrend) {
      condition2 = OP_BUY;
   }
   else if(trendCross == DownTrend) {
      condition2 = OP_SELL;
   }
   else {
      condition2 = mDefault;
   } 

   // 条件3：移動平均MAの短期が長期の上にあれば、ロング。反対ならショート。ただし、クロスした直後であること。
   trendCross = get_MAGCDC(0,        // 判断に使う時間軸 
                           1,        // 何シフト前から判断するか
                           Crossflag // クロスした直後ならtrue
                           ); 
   if(trendCross == UpTrend && Crossflag == true) {
      condition3 = OP_BUY;
   }
   else if(trendCross == DownTrend && Crossflag == true) {
      condition3 = OP_SELL;
   }
   else {
      condition3 = mDefault;
   }

   // 条件4：ランダム取引の条件を使う
   int flagRT = entryRT_only_Rand();
   RTMethod = 0;
   if(flagRT == OP_BUY) {
      condition4 = OP_BUY;
   }   
   else if(flagRT == OP_SELL) {
      condition4 = OP_SELL;
   }
   else {
      condition4 = mDefault;
   }
   
   // 条件5：ボリンジャーバンドの条件を使う(順張り）
   int flagBB = entryBB();
   if(flagBB == OP_BUY) {
      condition5 = OP_BUY;
   }   
   else if(flagBB == OP_SELL) {
      condition5 = OP_SELL;
   }
   else {
      condition5 = mDefault;
   }

   // 条件６：ボリンジャーバンドの条件を使う(逆張り）
   int flagBB_r = entryBB_r();
   if(flagBB_r== OP_BUY) {
      condition6 = OP_BUY;
   }   
   else if(flagBB_r == OP_SELL) {
      condition6 = OP_SELL;
   }
   else {
      condition6 = mDefault;
   }

   // 条件7：ボリンジャーバンドとボラティリティを使った順張り＋逆張り
   int flagRVI = entryRVI();
   if(flagRVI== OP_BUY) {
      condition7 = OP_BUY;
   }   
   else if(flagRVI == OP_SELL) {
      condition7 = OP_SELL;
   }
   else {
      condition7 = mDefault;
   }


   // 条件8：PinBarの条件を使う
   int flagPinBar = entryPinBar();
   PinBarMethod = 7;// この変数名を外部パラメータ名として表示させないため、7に固定する。
   if(flagPinBar == OP_BUY) {
      condition8 = OP_BUY;
   }   
   else if(flagPinBar == OP_SELL) {
      condition8 = OP_SELL;
   }
   else {
      condition8 = mDefault;
   }


   int retValue;
   // -2:ショート
   if(BUYSELL_TYPE_JUDGE_METHOD == -2) {
      retValue = ORDER_TYPE_SELL;
   }

   // -1:ロング
   if(BUYSELL_TYPE_JUDGE_METHOD == -1) {
      retValue = ORDER_TYPE_BUY;
   }

   // 0:シグナルなし
   if(BUYSELL_TYPE_JUDGE_METHOD == 0) {
      retValue = NO_SIGNAL;
   }

   // 1:4時間足のトレンド利用
   if(BUYSELL_TYPE_JUDGE_METHOD == 1) {
      retValue = condition1;
   }
   
   // 2:4時間足のトレンドと長短期移動平均利用
   else if(BUYSELL_TYPE_JUDGE_METHOD == 2) {
      if(condition1 == OP_BUY && condition2 == OP_BUY) {
         retValue = OP_BUY;
      }
      else if(condition1 == OP_SELL && condition2 == OP_SELL) {
         retValue = OP_SELL;
      }
      else {
         retValue = mDefault;
      }
   }
   
   else if(BUYSELL_TYPE_JUDGE_METHOD == 3) {  
      if(condition1 == OP_BUY && condition3 == OP_BUY) {
         retValue = OP_BUY;
      }
      else if(condition1 == OP_SELL && condition3 == OP_SELL) {
         retValue = OP_SELL;
      }
      else {
         retValue = mDefault;
      }
   }

   // ランダム
   else if(BUYSELL_TYPE_JUDGE_METHOD == 4) {
      retValue = condition4;      
   }

   // ボリンジャーバンド（順張り）
   else if(BUYSELL_TYPE_JUDGE_METHOD == 5) {
      retValue = condition5;
   }

   // ボリンジャーバンド（逆張り）
   else if(BUYSELL_TYPE_JUDGE_METHOD == 6) {
      retValue = condition6;
   }

   // ボリンジャーバンドとボラティリティを使った順張り＋逆張り
   else if(BUYSELL_TYPE_JUDGE_METHOD == 7) {
      retValue = condition7;
   }

   // ヒゲの活用
   else if(BUYSELL_TYPE_JUDGE_METHOD == 8) {
      retValue = condition8;
   }
   
   else {
      retValue = mDefault;
   }

   // 最後までNO_SIGNALの場合に備えたデフォルト値上書き
   if(retValue != OP_BUY && retValue != OP_SELL) {
      retValue = mDefault;
   }
   
   // トレーディングラインを使った制限
   retValue = update_BuySellSignals_by_TradingLine(retValue);
   return retValue;
}



// 4時間足でトレンドで判断する記事が多いことから、追加
// トレンドを引数渡しされた時間軸mTFが4時間足以下なら、4時間足で判断する。
// mTFが4時間足以上なら、引数の時間軸で判断する。
int get_Trend_EMA_PERIODH4(int mTF, int mShift) {
   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、NoTrendとする。
   if(mTF < PERIOD_CURRENT || mTF > PERIOD_MN1) {
      return NoTrend;
   }

   if(mTF <= PERIOD_H4) {
      mTF = PERIOD_H4;
   }
   double EMA_1 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 1), global_Digits);
   double EMA_2 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 2), global_Digits);	
   double EMA_3 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 3), global_Digits);	
   double EMA_4 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 4), global_Digits);	
   double EMA_5 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 5), global_Digits);	
	
	
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

   if(flag == false) {
      return NoTrend;
   }
   else {
      if(slope > 0.0) {
         return UpTrend;
      }
      else if(slope < 0.0) {
         return DownTrend;
      }
      else {
         return NoTrend;
      }
   }
   return NoTrend;
}



// EMAを使い、GCの時は1、DCの時は-1、それ以外は0を返す
int get_MAGCDC(int mTimeframe ,  // 判断に使う時間軸 
               int mShift,     // 何シフト前から判断するか
               bool &mCross    // 判断した時点でちょうどGCかDCをしている時、true
                               ) {
   double mainValue    = NormalizeDouble(iMA(NULL,PERIOD_CURRENT,25,0,MODE_EMA,PRICE_CLOSE,mShift) , global_Digits);
   double signalValue  = NormalizeDouble(iMA(NULL,PERIOD_CURRENT,75,0,MODE_EMA,PRICE_CLOSE,mShift), global_Digits);
   double mainValue2   = NormalizeDouble(iMA(NULL,PERIOD_CURRENT,25,0,MODE_EMA,PRICE_CLOSE,mShift+1), global_Digits);
   double signalValue2 = NormalizeDouble(iMA(NULL,PERIOD_CURRENT,75,0,MODE_EMA,PRICE_CLOSE,mShift+1), global_Digits);
   // ゴールデンクロスかデッドクロスの時、mCrossをtrue
   if(mainValue2 < signalValue2 && mainValue > signalValue) {
      mCross = true;   
   }
   else if(mainValue2 > signalValue2 && mainValue < signalValue) {
      mCross = true;   
   }
   else {
      mCross = false;
   }
   
   // MA短期が長期線を上抜け→ゴールデンクロス（GC）
   // MA短期が長期線を下抜け→デッドクロス（DC）
   if(mainValue > signalValue) {
      return UpTrend;
   }
   else if(mainValue < signalValue) {
      return DownTrend;
   }
   else {
      return NoTrend; 
   }
   
   return NoTrend;
}



int check_ExternalParam() {
   if(MagicNumberTestCase001 <= 0) {
      printf( "エラーコード>%d<：：MagicNumberTestCase001=>%d<は0より大きくにしてください。" , __LINE__, MagicNumberTestCase001 );
      return INIT_FAILED;
   }
   if(SLIPPAGE < 0.0) {
      printf( "エラーコード>%d<：：SLIPPAGE=>%s<は0.0ポイント以上にしてください。" , __LINE__, DoubleToStr(SLIPPAGE, global_Digits) );
      return INIT_FAILED;
   }

   if(SPREAD_PIPS < 0.0) {
      printf( "エラーコード>%d<：：SPREAD_PIPS=>%s<は0.0 PIPS以上にしてください。" , __LINE__, DoubleToStr(SPREAD_PIPS, global_Digits) );
      return INIT_FAILED;
   }
   else {
      SPREAD_point = change_PIPS2Point(SPREAD_PIPS);
   }

   double minLots = MarketInfo(global_Symbol,MODE_MINLOT);
   if(LOTS < NormalizeDouble(minLots, global_Digits) ) {
      printf( "エラーコード>%d<：：LOTS=>%s<は最小値>%s<以上にしてください。" , __LINE__, 
               DoubleToStr(LOTS, global_Digits),
               DoubleToStr(minLots, global_Digits) );
      return INIT_FAILED;
   }

   double maxLots = MarketInfo(global_Symbol,MODE_MAXLOT);
   if(LOTS > NormalizeDouble(maxLots, global_Digits) ) {
      printf( "エラーコード>%d<：：LOTS=>%s<は最大値>%s<以下にしてください。" , __LINE__, 
               DoubleToStr(LOTS, global_Digits),
               DoubleToStr(maxLots, global_Digits) );
      return INIT_FAILED;
   }
//printf( "%d    最小ロット数=%s   最大ロット数=%s" , __LINE__, DoubleToStr(minLots, global_Digits), DoubleToStr(maxLots, global_Digits));
   if(LOTS_TIMES <= 0.0) {
      printf( "エラーコード>%d<：：LOTS_TIMES=>%s<は0.0より大きくしてください。" , __LINE__, DoubleToStr(LOTS_TIMES, global_Digits) );
      return INIT_FAILED;
   }

   if(NormalizeDouble(LOTS_TIMES, global_Digits) * NormalizeDouble(LOTS, global_Digits) < NormalizeDouble(minLots, global_Digits)) {
      printf( "エラーコード>%d<：：LOTS=>%s< × LOTS_TIMES=>%s< = >%s< は最小値>%s<以上にしてください。" , __LINE__, 
             DoubleToStr(LOTS, global_Digits), 
             DoubleToStr(LOTS_TIMES, global_Digits),
             DoubleToStr(LOTS * LOTS_TIMES, global_Digits * 2),
             DoubleToStr(minLots, global_Digits) 
             );
      return INIT_FAILED;
   }

   if(TP_PIPS < 0.0) {
      printf( "エラーコード>%d<：：TP_PIPS=>%s<は0.0PIPS以上にしてください。" , __LINE__, DoubleToStr(TP_PIPS, global_Digits) );
      return INIT_FAILED;
   }

   if(SL_PIPS < 0.0) {
      printf( "エラーコード>%d<：：SL_PIP=>%s<は0.0PIPS以上にしてください。" , __LINE__, DoubleToStr(SL_PIPS, global_Digits));
      return INIT_FAILED;
   }
   
   if(BUYSELL_TYPE_JUDGE_METHOD <= -3 || BUYSELL_TYPE_JUDGE_METHOD >= 9) {
      printf( "エラーコード>%d<：：BUYSELL_TYPE_JUDGE_METHOD=>%d<は1～8にしてください。" , __LINE__, BUYSELL_TYPE_JUDGE_METHOD);
      return INIT_FAILED;
   }

   if(MAX_ADDITIONAL_TRADE_LEVEL <= -1) {
      printf( "エラーコード>%d<：：BUYSELL_TYPE_JUDGE_METHOD=>%d<は0以上にしてください。" , __LINE__, MAX_ADDITIONAL_TRADE_LEVEL);
      return INIT_FAILED;
   }

   if(ADDITIONAL_TRADE_SWITCH <= -1 || ADDITIONAL_TRADE_SWITCH >= 5) {
      printf( "エラーコード>%d<：：ADDITIONAL_TRADE_SWITCH=>%d<は1～4にしてください。" , __LINE__, ADDITIONAL_TRADE_SWITCH);
      return INIT_FAILED;
   }


   return INIT_SUCCEEDED;
}

double change_Point2PIPS(double mPoint) {
   double ret = 0.0;
   ret = mPoint;
   if(global_Digits == 2 || global_Digits == 3){
      ret *= 100.0;
   }else if(global_Digits == 4 || global_Digits == 5){
      ret *= 10000.0;
   }
   return(ret);

}
double change_PIPS2Point(double mPips) {
// https://min-fx.jp/start/fx-pips/
// 米ドル/円やクロス円（ユーロ/円、ポンド/円など）の場合
// 1pip＝0.01円（1銭）
// 10 pips＝0.1円（10銭）
// 100 pips＝1円（100銭）
// 
// 一方、ユーロ/ドルやポンド/ドルなどの米ドルストレート通貨の場合、1pip＝0.0001ドル（0.01セント）
// を表しています。ユーロ/ドルのレートが1.1500ドルから1.1505ドルに上昇した場合も、5pips上昇したと言うことになります。
// 
// 米ドルストレート（ユーロ/ドル、ポンド/ドルなど）の場合
// 1pip＝0.0001ドル（0.01セント）
// 10pip＝0.001ドル（0.1セント）
// 100pip＝0.01ドル（1セント）

   double ret = mPips;
   if(global_Digits == 2 || global_Digits == 3){
      ret /= 100.0;
   }else if(global_Digits == 4 || global_Digits == 5){
      ret /= 10000.0;
   }

   return(ret);
}




// https://biolab.sakura.ne.jp/regression-correlation.html
// 配列とデータ数を基に、最小二乗法を使って、傾き(slope)と切片(intercept)を計算する。
// 傾き(slope) = {Σ(x - xの平均)(y - yの平均) }÷{Σ(x - xの平均)^2}
// 切片(intercept) = yの平均 - 傾き（slope)*xの平均
// 入力：(1)data=配列, (2)dataNum=データ数, (3)slope=傾き, (4)intercept=切片
//   　 ただし、(3)(4)は計算結果の返り値
// 出力：正常終了した場合はtrue、失敗した場合はfalse。
// ※
// ※
// ※ data[0]がx=0、data[1]がx=1というように、data[]にはグラフの左（xが小さい方）から右（xが大きい方）のデータが入っている前提。
// ※ そのため、シフトのようにxの値が大きいほど過去を意味する場合は、計算後に傾きの正負を反転させる必要あり。
// ※
// ※
bool calcRegressionLine(double &data[],   // data[]にはグラフの左（xが小さい方）から右（xが大きい方）のデータが入っている前提。
                        int dataNum,      // データ件数 
                        double &slope,    // 出力：傾き
                        double &intercept // 出力：切片
                        ) {
   slope     = DOUBLE_VALUE_MIN;
   intercept = DOUBLE_VALUE_MIN;
   
   // データ数が2未満の時は、異常終了。
   if(dataNum < 2) {
      return false;
   }

   int    i;
   double mean_x = 0.0; // インデックス。0からデータ個数まで。
   double mean_y = 0.0; // データ。data[x]の値。

   // x, yの平均を計算
   for(i = 0; i < dataNum; i++) {
      mean_x = mean_x + i;
      mean_y = mean_y + data[i];
   }
   mean_x = NormalizeDouble(mean_x / dataNum, global_Digits * 2);  // xの平均。
   mean_y = NormalizeDouble(mean_y / dataNum, global_Digits * 2);  // yの平均
   
   // 傾きの計算
   double sumXY = 0.0;
   double sumX2 = 0.0;
   for(i = 0; i < dataNum; i++) {
      sumXY = sumXY + NormalizeDouble((i - mean_x) * (data[i] - mean_y), global_Digits * 2);
      sumX2 = sumX2 + NormalizeDouble((i - mean_x) * (i - mean_x), global_Digits * 2);
   }
   if(sumX2 <= 0.0) {
      return false;
   }
   else {
      slope = NormalizeDouble(sumXY / sumX2, global_Digits * 2);
   }
   
   //　切片の計算
   intercept = NormalizeDouble(mean_y - slope * mean_x, global_Digits * 2);
   
   return true;
}

// https://biolab.sakura.ne.jp/regression-correlation.html
// 配列とデータ数を基に、最小二乗法を使って、傾き(slope)と切片(intercept)を計算する。
// 傾き(slope) = {Σ(x - xの平均)(y - yの平均) }÷{Σ(x - xの平均)^2}
// 切片(intercept) = yの平均 - 傾き（slope)*xの平均
// 入力：(1)data=配列, (2)dataNum=データ数, (3)slope=傾き, (4)intercept=切片
//   　 ただし、(3)(4)は計算結果の返り値
// 出力：正常終了した場合はtrue、失敗した場合はfalse。
// ※
// ※ 重回帰分析 y = slope * x + interceptを満たすslopeとinterceptを求める
// ※ 電卓は、https://keisan.casio.jp/exec/system/1402032384
// ※ y軸data_y[i]のx軸がdata_x[i]というように、2数が対応するデータが入っている前提。
// ※ 類似の関数calcRegressionLine(double &data[], int dataNum, double &slope, double &intercept)と異なり、
// ※ 配列内の順番は意識しない。
// ※
bool calcRegressionLine(double &data_y[],  // 入力：y = slope * x + interceptのy
                        double &data_x[],  // 入力：y = slope * x + interceptのx
                        int    dataNum,    // 入力：x, yのデータ件数
                        double &slope,     // 出力：傾き 
                        double &intercept  // 出力：切片
                       ) {
   slope = DOUBLE_VALUE_MIN;
   intercept = DOUBLE_VALUE_MIN;
   
   // データ数が2未満の時は、異常終了。
   if(dataNum < 2) {
      return false;
   }

   int    i;
   double mean_x = 0.0; // インデックス。0からデータ個数まで。
   double mean_y = 0.0; // データ。data[x]の値。

   // x, yの平均を計算
   for(i = 0; i < dataNum; i++) {
      mean_x = NormalizeDouble(mean_x, global_Digits*2) + NormalizeDouble(data_x[i], global_Digits*2);
      mean_y = NormalizeDouble(mean_y, global_Digits*2) + NormalizeDouble(data_y[i], global_Digits*2);
   }
   mean_x = NormalizeDouble(mean_x / dataNum, global_Digits*2);  // xの平均。
   mean_y = NormalizeDouble(mean_y / dataNum, global_Digits*2);  // yの平均

   // 傾きの計算
   double sumXY = 0.0;
   double sumX2 = 0.0;
   for(i = 0; i < dataNum; i++) {
      sumXY = sumXY + NormalizeDouble((NormalizeDouble(data_x[i], global_Digits) - mean_x) * (NormalizeDouble(data_y[i], global_Digits) - mean_y), global_Digits * 2);
      sumX2 = sumX2 + NormalizeDouble((NormalizeDouble(data_x[i], global_Digits) - mean_x) * (NormalizeDouble(data_x[i], global_Digits) - mean_x), global_Digits * 2);
   }
   if(sumX2 <= 0.0) {
      return false;
   }
   else {
      slope = NormalizeDouble(sumXY / sumX2, global_Digits*2);
   }
   
   //　切片の計算
   intercept = NormalizeDouble(mean_y - slope * mean_x, global_Digits*2);
   
   return true;
}

// 
// スプレッド、レバレッジを鑑みて、新規取引可能かどうかを判断する。
// 取引可能な場合はtrue。不可能な場合はfalse。
bool judge_Tradable(int mLevel   // 1:スプレッドのみ。2：スプレッドとレバレッジ
   ) {
   if(mLevel <= 0 || mLevel > 2) {
      return false;
   }

   bool ret = true; // この関数の返り値

   // 
   // スプレッドが、外部パラメータSPREAD_PIPS以上であればfalseを返す。
   // 
   bool retSpread = true;
string tmpretSpread = "true";
   if(NormalizeDouble(change_Point2PIPS(MathAbs(Bid - Ask)), global_Digits) >= SPREAD_PIPS) {
      printf( "エラーコード>%d<：：スプレッド>%s<PIPSがSPREAD_PIPS=>%s<PIPSより大きいため約定不可" , __LINE__,
                DoubleToStr(change_Point2PIPS(MathAbs(Bid - Ask)), global_Digits),
                DoubleToStr(SPREAD_PIPS, global_Digits)
                );
      retSpread = false; 
tmpretSpread = "false";
   }

   // 
   // 実効レバレッジが、外部パラメータMAX_Leverageより大きければfalseを返す。
   // 
   double Leverage = GetRoughEffectiveLeverage();
   double retLeverage = true;
string tmpretLeverage = "true";
   if(Leverage < 0 
      || NormalizeDouble(MAX_Leverage, global_Digits) < NormalizeDouble(Leverage, global_Digits)
      ) {
//printf( ">%d<　Leverage=%s > MAX_Leverage=%s" , __LINE__, DoubleToStr(Leverage, global_Digits) , DoubleToStr(MAX_Leverage, global_Digits));      
      retLeverage = false; 
//tmpretLeverage = "false";
   } 

   // レベル１：スプレッドの条件のみを判断材料とする。
   if(mLevel == 1) {
      if(retSpread == false) {
         ret = false;
      }
   }

   // レベル２：スプレッドとレバレッジの条件を判断材料とする。
   else if(mLevel == 2) {
      if(retSpread == false || retLeverage == false) {
         ret = false;
//printf( ">%d<　retSpread=%s retLeverage=%s" , __LINE__, tmpretSpread , tmpretLeverage);      
         
      }
   }

   return ret;
}


/* ------------------------------------------------------------------
 * 実効レバレッジ計算
 * ------------------------------------------------------------------ */
// 実効レバレッジ = 取引総額 ÷ 有効証拠金
// 取引総額 ≒ 取引証拠金総額 × 口座のレバレッジ
double GetRoughEffectiveLeverage() {
   double ret = NormalizeDouble(AccountMargin(), global_Digits) * NormalizeDouble(GetTrueAccountLeverage(), global_Digits) / NormalizeDouble(AccountEquity(), global_Digits);
   
   if(ret < 0.0) {
      return -1.0;
   }

   return ret;
}

double GetTrueAccountLeverage() {
  // AccountLeverage()が不正確なサーバは、固定値を返す
  string serverName = AccountServer();
  if (StringCompare(serverName, "SaxoBank-Live") == 0) {
     return 25.0;
  }

  // AccountLeverage()が正しい値を返すサーバはAccountLeverageの値を使用
  return NormalizeDouble(AccountLeverage(), global_Digits);
}


int entryBB() {
   int ret;
   //ボリンジャーバンドの値を取得
   double BB3UP = iBands(global_Symbol,0,21,3,0,PRICE_CLOSE,MODE_UPPER,0); //3σの上側
   double BB3LO = iBands(global_Symbol,0,21,3,0,PRICE_CLOSE,MODE_LOWER,0); //3σの下側        
        
   //Askがボリンジャーバンドの上3σタッチで買いサイン
   if(NormalizeDouble(BB3UP, global_Digits) < NormalizeDouble(Ask, global_Digits))  {
      ret = OP_BUY;
   }
   //Bidがボリンジャーバンドの下3σタッチで売りサイン
   else if(NormalizeDouble(BB3LO, global_Digits) > NormalizeDouble(Bid, global_Digits)) {
      ret = OP_SELL;
   }
   //それ以外は何もしない
   else{
      ret = -1;
   }
   
   return ret;
}


int entryBB_r() {
   int ret;
   //ボリンジャーバンドの値を取得
   double BB3UP = iBands(global_Symbol,0,21,3,0,PRICE_CLOSE,MODE_UPPER,0); //3σの上側
   double BB3LO = iBands(global_Symbol,0,21,3,0,PRICE_CLOSE,MODE_LOWER,0); //3σの下側        
   double BB2UP = iBands(global_Symbol,0,21,2,0,PRICE_CLOSE,MODE_UPPER,0); //2σの上側
   double BB2LO = iBands(global_Symbol,0,21,2,0,PRICE_CLOSE,MODE_LOWER,0); //2σの下側        

        
   //Askがボリンジャーバンドの下(-3σタッチと-2σ内)で買いサイン
   if(NormalizeDouble(BB3LO, global_Digits) < NormalizeDouble(Ask, global_Digits)
      &&
      NormalizeDouble(BB2LO, global_Digits) > NormalizeDouble(Ask, global_Digits)
   )  {
      ret = OP_BUY;
   }
   //Bidがボリンジャーバンドの上(+3σタッチと+2σ)で売りサイン
   else if(NormalizeDouble(BB3UP, global_Digits) > NormalizeDouble(Bid, global_Digits) 
            &&
           NormalizeDouble(BB2UP, global_Digits) < NormalizeDouble(Bid, global_Digits) ){
            
      ret = OP_SELL;
   }
   //それ以外は何もしない
   else{
      ret = -1;
   }
   
   return ret;
}



// 引数で渡した取引LOTS数が、設定可能最大値を上回っていたら最大値にする。
// また、設定可能最小値を下回っていたら最小値にする。
void check_LotsMaxMin(double &mLots) {
   double lotsMIN = MarketInfo(global_Symbol,MODE_MINLOT); // ロットの最小値  
   double lotsMAX = MarketInfo(global_Symbol,MODE_MAXLOT); // ロットの最大値
   
   if(NormalizeDouble(mLots, global_Digits) < NormalizeDouble(lotsMIN, global_Digits) ) {
      mLots = NormalizeDouble(lotsMIN, global_Digits);
   }
   if(NormalizeDouble(mLots, global_Digits) > NormalizeDouble(lotsMAX, global_Digits) ) {
      mLots = NormalizeDouble(lotsMAX, global_Digits);
   }
}   
   

// シフトmShiftにおいて、SMA20とSMA50で雲が発生しているかを判断する。
// ・水色雲：SMA50よりSMA20が上にある上昇サイン＝UpTrendを返す
// ・茶色雲：SMA50よりSMA20が下にある下落サイン＝DownTrendを返す
// ・上記以外はNoTrendを返す。
int get_TrendCloud(string mSymbol,    // 通貨ペア
                   int    mTimeFrame, // 時間軸
                   int    mShift,     // 雲の発生を判断するシフト
                   double &mSMA20,    // 出力：雲の発生に判断したSMA20
                   double &mSMA50     // 出力：雲の発生に判断したSMA50
                   ) {
   mSMA20 = iMA( global_Symbol,// 通貨ペア
                 mTimeFrame,   // 時間軸
                 20,           // MAの平均期間
                 0,            // MAシフト
                 MODE_SMA,     // MAの平均化メソッド
                 PRICE_CLOSE,  // 適用価格
                 mShift        // シフト
                 );
   mSMA20 = NormalizeDouble(mSMA20, global_Digits);
                        
   mSMA50 = iMA( global_Symbol,// 通貨ペア
                 mTimeFrame,    // 時間軸
                 50,            // MAの平均期間
                 0,             // MAシフト
                 MODE_SMA,      // MAの平均化メソッド
                 PRICE_CLOSE,   // 適用価格
                 mShift         // シフト
                 );
   mSMA50 = NormalizeDouble(mSMA50, global_Digits);

   // ・水色雲：SMA50よりSMA20が上にある上昇サインUpTrend
   // ・茶色雲：SMA50よりSMA20が下にある下落サインDownTrend
   if(mSMA20 > mSMA50) {
      return UpTrend;   // ・水色雲：SMA50よりSMA20が上にある上昇サイン
   }
   else if(mSMA20 < mSMA50) {
      return DownTrend; // ・茶色雲：SMA50よりSMA20が下にある下落サイン
   }
   else {
      return NoTrend;
   }

   return NoTrend;
}

// トレーディングラインを使った制限
int update_BuySellSignals_by_TradingLine(int mBuySell) {
   int ret = mBuySell;
   
   bool flag_calc_TradingLines = calc_TradingLines(global_Symbol, 
                                                   0, 
                                                   50, 
                                                   g_past_max, 
                                                   g_past_maxTime, 
                                                   g_past_min, 
                                                   g_past_minTime, 
                                                   g_past_width, 
                                                   g_long_Min, 
                                                   g_long_Max, 
                                                   g_short_Min, 
                                                   g_short_Max);
   
   if(mBuySell == OP_BUY) {
      if(Ask >= g_long_Min && Ask <= g_long_Max) {
         // 現状維持
      }
      else {
         ret = NO_SIGNAL;
      }
   }
   else if(mBuySell == OP_BUY) {
      if(Bid >= g_long_Min && Bid <= g_long_Max) {
         // 現状維持      
      }
      else {
         ret = NO_SIGNAL;
      }
   }
                               
   return ret;
}
   
/////////////////////////////////////////////////////////////////////////
////////////////////////////Puer_PinBAR.mqhからコピー////////////////////////
/////////////////////////////////////////////////////////////////////////
// No3用の条件を満たす最新の値。
int      PinBarNo3_Signal = INT_VALUE_MIN;
double   PinBarNo3_Price  = DOUBLE_VALUE_MIN;
datetime PinBarNo3_Time   = 0;

void init_PinBarNo3Params() {
   PinBarNo3_Signal = INT_VALUE_MIN;
   PinBarNo3_Price = DOUBLE_VALUE_MIN;
   PinBarNo3_Time = 0;
}
// 25PinBAR
int    PinBarMethod       = 7;     // 1:No1：順張りピンバー手法, 2:No3 ピンバー押し・戻り手法, 3:1と2, 4:NoX 予約
                                   // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=NoX予約, 101(5)=No1とNoX  
int    PinBarTimeframe    = 0;     // 計算に用いる時間軸
int    PinBarBackstep     = 15;    // 大陽線、大陰線が発生したことを何シフト前まで確認するか
double PinBarBODY_MIN_PER = 90.0;  // 実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
double PinBarPIN_MAX_PER  = 20.0;  // 実体が髭のナンパ―セント以下であればピンと判断するか

// 99RandomTrade
int    RTMethod = 2;           // 1:ランダムに売買を判断する。2:トレンドも考慮して売買を判断する
double RTthreshold_PER = 50.0; // 売買判断をする閾値（threshold）。乱数(0～32767)が、32767 * RTthreshold_PER / 100以上なら売り。未満なら、買い。



int entryPinBar() {
   int mSignal  = NO_SIGNAL;
   // PinBarMethod
   // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5
   // 110(6)=No3とNo5, 111=No1とNo3とNo5  
   if(PinBarMethod == 1) {
      mSignal = entryPinBar_No1(0);
      return mSignal;
   }
   else if(PinBarMethod == 2) {
      mSignal = entryPinBar_No3(0);
      return mSignal;
   }
   else if(PinBarMethod == 3) {
      mSignal = entryPinBar_No1(0);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No3(0);
      return mSignal;
   }
   else if(PinBarMethod == 4) {
      mSignal = entryPinBar_No5(0);
      return mSignal;
   }
   else if(PinBarMethod == 5) {
      mSignal = entryPinBar_No1(0);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No5(0);
      return mSignal;
   }
   else if(PinBarMethod == 6) {
      mSignal = entryPinBar_No3(0);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No5(0);
      if(mSignal != NO_SIGNAL) {
      }       
      return mSignal;
   }
   else if(PinBarMethod == 7) {
      mSignal = entryPinBar_No1(0);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No3(0);
      if(mSignal != NO_SIGNAL) {
         return mSignal;
      }
      mSignal = entryPinBar_No5(0);
      return mSignal;
   }
      
   return NO_SIGNAL;
}




// ※シフト0の売買判断において使用する前提の関数。
// シフト2から直前数本前のシフトmPinBarBackstepまで検索して、大陽線または大陰線があれば、trueを返す。
// 実体が上ヒゲよりも長いローソク足を「大陽線」とする。上ヒゲが実体よりも長い場合は見送り。実体と上ヒゲがほとんど同じ長さだった場合も見送る。下ヒゲの長さは考慮しなくてよい。
// 実体が下ヒゲよりも長いローソク足を「大陽線」とする。下ヒゲが実体よりも長い場合は見送り。実体と下ヒゲがほとんど同じ長さだった場合も見送る。上ヒゲの長さは考慮しなくてよい。
// ただし、探しているの線とは逆の線が先に見つかった場合（陽線を探す時に、より近い時刻に陰線が見つかる）はFALSEを返す。
bool exist_BigBody(int    mTimeFrame,
                   int    mSignal,             // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                   int    mPinBarBackstep,     // 何本前のシフトまで、陽線又は、陰線を探すか。
                   double mPinBarBODY_MIN_PER) {// 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
   if(mPinBarBackstep < 2) {
      return false;
   } 
   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、falseとする。
   if(mTimeFrame < PERIOD_CURRENT || mTimeFrame > PERIOD_MN1) {
      return false;
   }

   if(mSignal != BUY_SIGNAL && mSignal != SELL_SIGNAL) {
      return false;
   }

   int i;
   bool flag_is_BigBody_BUYSIGNAL  = false;  // 大陽線の時、true
   bool flag_is_BigBody_SELLSIGNAL = false;  // 大陰線の時、true

   for(i = 2; i < 2 + mPinBarBackstep; i++) {
      // 注目したシフトが大陽線かを調べる
      flag_is_BigBody_BUYSIGNAL = is_BigBody(mTimeFrame,
                                             BUY_SIGNAL,         // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                                             i,                  // このシフトが、大陽線又は、大陰線を判断する。
                                             mPinBarBODY_MIN_PER // 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
                                             ); 
      //
      // 注目したシフトが大陽線の場合      
      //
      if(flag_is_BigBody_BUYSIGNAL == true) {
         // 引数mSignalが大陽線を探しているのであれば、trueを返す
         if(mSignal == BUY_SIGNAL) {
            return true;
         }
         // 引数mSignalが大陰線を探しているのであれば、falseを返す
         else if(mSignal == SELL_SIGNAL) {
            return false;
         }
      }
      else {   // 注目したシフトが大陽線ではなかったので、大陰線を調べる
         // 注目したシフトが大陽線かを調べる
         flag_is_BigBody_SELLSIGNAL = is_BigBody(mTimeFrame,
                                                 SELL_SIGNAL,         // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                                                 i,                  // このシフトが、大陽線又は、大陰線を判断する。
                                                 mPinBarBODY_MIN_PER // 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
                                                 ); 
         //
         // 大陰線の場合      
         //
         if(flag_is_BigBody_SELLSIGNAL== true) {
            // 引数mSignalが大陰線を探しているのであれば、trueを返す
            if(mSignal == SELL_SIGNAL) {
               return true;
            }
            // 引数mSignalが大陽線を探しているのであれば、falseを返す
            else if(mSignal == BUY_SIGNAL) {
               return false;
            }
         }
      }
   }   

   // ループ内で、大陽線も大陰線も見つからなかったのでfalseを返す。
   return false;
}



// 指定したシフトmShiftが、大陽線または大陰線があれば、trueを返す。
// 実体が上ヒゲよりも長いローソク足を「大陽線」とする。上ヒゲが実体よりも長い場合は見送り。実体と上ヒゲがほとんど同じ長さだった場合も見送る。下ヒゲの長さは考慮しなくてよい。
// 実体が下ヒゲよりも長いローソク足を「大陽線」とする。下ヒゲが実体よりも長い場合は見送り。実体と下ヒゲがほとんど同じ長さだった場合も見送る。上ヒゲの長さは考慮しなくてよい。
// ただし、探しているの線とは逆の線が先に見つかった場合（陽線を探す時に、より近い時刻に陰線が見つかる）はFALSEを返す。
bool is_BigBody(int    mTimeFrame,
                int    mSignal,            // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                int    mShift,             // このシフトが、大陽線又は、大陰線を判断する。
                double mPinBarBODY_MIN_PER // 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
                ) {
   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、falseとする。
   if(mTimeFrame < PERIOD_CURRENT || mTimeFrame > PERIOD_MN1) {
      return false;
   }

   if(mSignal != BUY_SIGNAL && mSignal != SELL_SIGNAL) {
      return false;
   }

   double close_i = DOUBLE_VALUE_MIN;
   double open_i  = DOUBLE_VALUE_MIN;
   double high_i  = DOUBLE_VALUE_MIN;
   double low_i   = DOUBLE_VALUE_MIN;
   double high_close_i = DOUBLE_VALUE_MIN;  // 大陽線を判断する時の上髭
   double low_close_i  = DOUBLE_VALUE_MIN;  // 大陰線を判断する時の下髭
   double body_i  = DOUBLE_VALUE_MIN; // 実体部分

   close_i = NormalizeDouble(iClose(global_Symbol, mTimeFrame, mShift), global_Digits);    
   open_i  = NormalizeDouble(iOpen(global_Symbol, mTimeFrame, mShift), global_Digits);

   //
   // 大陽線の場合      
   //
   // 陽線であること
   if(close_i > open_i){
      high_i = NormalizeDouble(iHigh(global_Symbol, mTimeFrame, mShift), global_Digits); 
      low_i  = NormalizeDouble(iLow(global_Symbol, mTimeFrame, mShift), global_Digits);
      high_close_i = high_i - close_i;
      body_i = close_i - open_i;
      // 実体部分が、高値安値のmPinBarBODY_MIN_PERパーセントより大きいこと
      if( body_i > NormalizeDouble((high_i - low_i) * mPinBarBODY_MIN_PER / 100.0, global_Digits) 
         // かつ、上ヒゲより実体の方が長いこと
         && high_close_i < body_i ) {
         // 陽線を探していたのであれば、trueを返す
         if(mSignal == BUY_SIGNAL) {
            return true;
         }
         // 陰線を探していたのであれば、falseを返す
         else {
            return false;
         }
      }
      else {
            return false;      
      }
   }
   //
   // 大陰線の場合      
   //
   // 陰線であること
   else if(close_i < open_i){
      high_i = NormalizeDouble(iHigh(global_Symbol, mTimeFrame, mShift), global_Digits); 
      low_i  = NormalizeDouble(iLow(global_Symbol, mTimeFrame, mShift), global_Digits);
      low_close_i = close_i - low_i;
      body_i = open_i - close_i;
      // 実体部分が、高値安値のmPinBarBODY_MIN_PERパーセントより大きいこと
      if( body_i > NormalizeDouble((high_i - low_i) * mPinBarBODY_MIN_PER / 100.0, global_Digits) 
         // かつ、下ヒゲより実体の方が長いこと
         && low_close_i < body_i ) {
         
         // 陰線を探していたのであれば、trueを返す
         if(mSignal == SELL_SIGNAL) {
            return true;
         }
         // 陽線を探していたのであれば、falseを返す
         else {
            return false;
         }
      }
      else {
         return false;
      }
   }
   // 陽線でも陰線でもない場合
   else {
      return false;
   }

   return false;
}


// シフトmShiftから探し始めて、直前数本前のシフトmPinBarBackstepまで検索して、大陽線または大陰線があれば、trueを返す。
// 実体が上ヒゲよりも長いローソク足を「大陽線」とする。上ヒゲが実体よりも長い場合は見送り。実体と上ヒゲがほとんど同じ長さだった場合も見送る。下ヒゲの長さは考慮しなくてよい。
// 実体が下ヒゲよりも長いローソク足を「大陽線」とする。下ヒゲが実体よりも長い場合は見送り。実体と下ヒゲがほとんど同じ長さだった場合も見送る。上ヒゲの長さは考慮しなくてよい。
// ただし、探しているの線とは逆の線が先に見つかった場合（陽線を探す時に、より近い時刻に陰線が見つかる）はFALSEを返す。
bool exist_BigBody(int    mTimeFrame,
                   int    mSignal,             // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                   int    mShift,              // 陽線、陰線を探し始めるシフト番号
                   int    mPinBarBackstep,     // 何本前のシフトまで、陽線又は、陰線を探すか。
                   double mPinBarBODY_MIN_PER) {// 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
   if(mPinBarBackstep <= 0) {
      return false;
   } 
   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、falseとする。
   if(mTimeFrame < PERIOD_CURRENT || mTimeFrame > PERIOD_MN1) {
      return false;
   }

   if(mSignal != BUY_SIGNAL && mSignal != SELL_SIGNAL) {
      return false;
   }

   int i;
   bool flag_is_BigBody_BUYSIGNAL  = false;  // 大陽線の時、true
   bool flag_is_BigBody_SELLSIGNAL = false;  // 大陰線の時、true

   for(i = mShift; i < mShift + mPinBarBackstep; i++) {
      // 注目したシフトが大陽線かを調べる
      flag_is_BigBody_BUYSIGNAL = is_BigBody(mTimeFrame,
                                             BUY_SIGNAL,         // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                                             i,                  // このシフトが、大陽線又は、大陰線を判断する。
                                             mPinBarBODY_MIN_PER // 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
                                             ); 
      //
      // 注目したシフトが大陽線の場合      
      //
      if(flag_is_BigBody_BUYSIGNAL == true) {
         // 引数mSignalが大陽線を探しているのであれば、trueを返す
         if(mSignal == BUY_SIGNAL) {
            return true;
         }
         // 引数mSignalが大陰線を探しているのであれば、falseを返す
         else if(mSignal == SELL_SIGNAL) {
            return false;
         }
      }
      else {   // 注目したシフトが大陽線ではなかったので、大陰線を調べる
         // 注目したシフトが大陽線かを調べる
         flag_is_BigBody_SELLSIGNAL = is_BigBody(mTimeFrame,
                                                 SELL_SIGNAL,         // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                                                 i,                  // このシフトが、大陽線又は、大陰線を判断する。
                                                 mPinBarBODY_MIN_PER // 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
                                                 ); 
         //
         // 大陰線の場合      
         //
         if(flag_is_BigBody_SELLSIGNAL== true) {
            // 引数mSignalが大陰線を探しているのであれば、trueを返す
            if(mSignal == SELL_SIGNAL) {
               return true;
            }
            // 引数mSignalが大陽線を探しているのであれば、falseを返す
            else if(mSignal == BUY_SIGNAL) {
               return false;
            }
         }
      }
   }   

   // ループ内で、大陽線も大陰線も見つからなかったのでfalseを返す。
   return false;
}




int entryPinBar_No1(int mShift) {
// No1：順張りピンバー手法
// 
// https://fx-works.jp/wp-content/uploads/2020/09/ebook.pdf
// 買いの場合
// １．1つ前のシフトが、SMA50、SMA20、SMA5 のパーフェクトオーダーを確認（下から SMA50、SMA20、SMA5 の順番に並ぶ）
// ２．1つ前のシフトのCloseが、SMA20、SMA5 の上でレートが推移している
// ３．2つ以上前の直近で「大陽線」の出現
// ４．1つ前で上向き矢印ピンバーの出現
// ５．次の足の始値で買いエントリー
// 
// 売りの場合
// １．1つ前のシフトが、SMA50、SMA20、SMA5 のパーフェクトオーダーを確認（上から SMA50、SMA20、SMA5 の順番に並ぶ）
// ２．1つ前のシフトのCloseが、SMA20、 SMA5 の下でレートが推移している
// ３．2つ以上前の直近で「大陰線」の出現
// ４．1つ前で下向き矢印ピンバーの出現
// ５．次の足の始値で売りエントリー

   int mSignal  = NO_SIGNAL;
   int mTimeFrame = getTimeFrame(PinBarTimeframe);
      
   datetime nowDT = iTime(global_Symbol, mTimeFrame, 0 + mShift);
   // 1つ前のシフトの移動平均を取得する。
   double SMA05 = iMA( global_Symbol,// 通貨ペア
                       mTimeFrame,   // 時間軸
                       5,   // MAの平均期間
                       0,            // MAシフト
                       MODE_SMA,     // MAの平均化メソッド
                       PRICE_CLOSE,  // 適用価格
                       1 + mShift    // シフト
                      );
   double SMA20 = iMA( global_Symbol,// 通貨ペア
                       mTimeFrame,   // 時間軸
                       20,   // MAの平均期間
                       0,            // MAシフト
                       MODE_SMA,     // MAの平均化メソッド
                       PRICE_CLOSE,  // 適用価格
                       1 + mShift    // シフト
                      );
   double SMA50 = iMA( global_Symbol,// 通貨ペア
                       mTimeFrame,   // 時間軸
                       50,   // MAの平均期間
                       0,            // MAシフト
                       MODE_SMA,     // MAの平均化メソッド
                       PRICE_CLOSE,  // 適用価格
                       1 + mShift    // シフト
                      );
   double close_1 = iClose(global_Symbol, mTimeFrame, 1 + mShift);         
   bool flag_exist_BigBody = false;
   bool flag_is_PinBar     = false;     
   bool flag_Trend         = NoTrend; // 1つ上の足のトレンドを計算した結果。    
   int  upper_TF           = get_UpperLowerPeriod_ENUM_TIMEFRAMES(mTimeFrame, 1); // 1つ上の時間軸

   // 買いの場合（1つ上の時間軸が下落でないこと）
   // １．1つ前のシフトが、SMA50、SMA20、SMA5 のパーフェクトオーダーを確認（下から SMA50、SMA20、SMA5 の順番に並ぶ）
   // ２．1つ前のシフトのCloseが、SMA20、SMA5 の上でレートが推移している
   // ３．2つ以上前の直近で「大陽線」の出現。実体が上ヒゲよりも長いローソク足を「大陽線」とする。上ヒゲが実体よりも長い場合は見送り。実体と上ヒゲがほとんど同じ長さだった場合も見送る。下ヒゲの長さは考慮しなくてよい。
   // ４．1つ前のシフトで、上向き矢印ピンバーの出現
   // ５．次の足の始値で買いエントリー   
   if(NormalizeDouble(SMA05, global_Digits) >= NormalizeDouble(SMA20, global_Digits) 
      &&  
      NormalizeDouble(SMA20, global_Digits) >= NormalizeDouble(SMA50, global_Digits) 
      && 
      NormalizeDouble(SMA50, global_Digits) > 0.0) {
      if(NormalizeDouble(close_1, global_Digits) > NormalizeDouble(SMA20 , global_Digits)
         &&
         NormalizeDouble(close_1, global_Digits) > NormalizeDouble(SMA05 , global_Digits) ) {
         flag_exist_BigBody = 
            // シフト2かそれより前の直近が大陽線であればtrue
            exist_BigBody(mTimeFrame,         // 計算用時間軸
                          BUY_SIGNAL,         // 大陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                          2 + mShift,         // mShiftから2つ前のシフトから陽線を探す。
                          PinBarBackstep,     // mShiftから2つ前のシフトから何本前のシフトまで、陽線又は、陰線を探すか。
                          PinBarBODY_MIN_PER);// 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
         // シフト2以前の直近が大陽線で、シフト1が上向き矢印ピンバーを形成していたら、現時点で買いシグナルを出す。
         if(flag_exist_BigBody == true) {
            flag_is_PinBar = 
               is_PinBar(mTimeFrame,         // 計算用時間軸
                         BUY_SIGNAL,         // 陽線のPinBARを探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                         1 + mShift,         // mShiftから1つ前のシフトがPinBarを形成しているか
                         PinBarPIN_MAX_PER); // 実体部分(始値と終値の差）が最高値と最安値の何％以下ならPinBARとみなすか

            flag_Trend = get_Trend_EMA_PERIODH4(0, mShift);
            // シフト１が上向き矢印ピンバーを形成し、1つ上の足が下降トレンドでなければ買いシグナルを出す。
            if(flag_is_PinBar == true && flag_Trend == UpTrend) {
               return BUY_SIGNAL;
            }
         }
      }
   }
  
   // 売りの場合（1つ上の時間軸が上昇でないこと）
   // １．1つ前のシフトが、SMA50、SMA20、SMA5 のパーフェクトオーダーを確認（上から SMA50、SMA20、SMA5 の順番に並ぶ）
   // ２．1つ前のシフトのCloseが、SMA20、 SMA5 の下でレートが推移している
   // ３．2つ以上前の直近で「大陰線」の出現。実体が下ヒゲよりも長いローソク足を「大陽線」とする。下ヒゲが実体よりも長い場合は見送り。実体と下ヒゲがほとんど同じ長さだった場合も見送る。上ヒゲの長さは考慮しなくてよい。
   // ４．1つ前のシフトで、下向き矢印ピンバーの出現
   // ５．次の足の始値で売りエントリー
   if(NormalizeDouble(SMA05, global_Digits) <= NormalizeDouble(SMA20, global_Digits) 
      &&  
      NormalizeDouble(SMA20, global_Digits) <= NormalizeDouble(SMA50, global_Digits) 
      && 
      NormalizeDouble(SMA05, global_Digits) > 0.0) {
      if(NormalizeDouble(close_1, global_Digits) < NormalizeDouble(SMA20 , global_Digits)
         &&
         NormalizeDouble(close_1, global_Digits) < NormalizeDouble(SMA05 , global_Digits) ) {
         flag_exist_BigBody = 
            // シフト2かそれより前の直近が大陰線であればtrue
            exist_BigBody(mTimeFrame,         // 計算用時間軸
                          SELL_SIGNAL,        // 陽線を探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                          2 + mShift,         // mShiftから2つ前のシフトから陽線を探す。
                          PinBarBackstep,     // mShiftから2つ前のシフトから何本前のシフトまで、陽線又は、陰線を探すか。
                          PinBarBODY_MIN_PER);// 実体部分(始値と終値の差）が最高値と最安値の何％以上なら陽線又は、陰線とみなすか
         // シフト2以前の直近が大陰線で、シフト1が下向き矢印ピンバーを形成していたら、現時点で売りシグナルを出す。    
         if(flag_exist_BigBody == true) {
            flag_is_PinBar = 
               is_PinBar(mTimeFrame,         // 計算用時間軸
                         SELL_SIGNAL,        // 陽線のPinBARを探す時は、BUY_SIGNAL。陰線を探す時は、SELL_SIGNAL
                         1 + mShift,         // mShiftから1つ前のシフトがPinBarを形成しているか
                         PinBarPIN_MAX_PER); // 実体部分(始値と終値の差）が最高値と最安値の何％以下ならPinBARとみなすか
                         
            flag_Trend = get_Trend_EMA_PERIODH4(0, mShift);
            // シフト１が下向き矢印ピンバーを形成し、1つ上の足が上昇トレンドでなければ買いシグナルを出す。             
            if(flag_is_PinBar == true && flag_Trend == DownTrend) {
               return SELL_SIGNAL;
            }
         }
      }
   }

   return NO_SIGNAL;
}	




int entryPinBar_No3(int mShift) {
   int mTimeFrame = getTimeFrame(PinBarTimeframe);
   int upper_TF = get_UpperLowerPeriod_ENUM_TIMEFRAMES(mTimeFrame, 1); // 1つ上の時間軸
   int mSignal  = NO_SIGNAL;
   int trendCloud = NoTrend;
   double SMA05 = DOUBLE_VALUE_MIN;
   double SMA20 = DOUBLE_VALUE_MIN;
   double SMA50 = DOUBLE_VALUE_MIN;  
   int ret = NO_SIGNAL;
   datetime dtNow = iTime(global_Symbol, mTimeFrame, mShift);  // 本来はTimeLocal();だが、mShiftシフト手前の時間を取得できないため、iTime関数で代理
   
// 1．PinBarNo3_Timeが現時点より前で、0より大きければ、現在のASK/BIDを使ってシグナルを判断
//   初期値は、ret = NO_SIGNAL
// 　PinBarSignal = 1の時、現時点も水色雲かつASKがPinBarNo3_Price以下の時、BUY_SIGNALを返す準備　→　ret = BUY_SIGNAL
// 　PinBarSignal = 2の時、ASKがPinBarNo3_Price以下の時、BUY_SIGNALを返す準備　→　ret = BUY_SIGNAL
// 　PinBarSignal = 3の時、現時点も茶色雲かつBIDがPinBarNo3_Price以上の時、SELL_SIGNALを返す　→　ret = SELL_SIGNAL
// 　PinBarSignal = 4の時、ASKがPinBarNo3_Price以上の時、SELL_SIGNALを返す　→　ret = SELL_SIGNAL
//  retが、NO_SIGNAL以外の時、PinBarNo3_Signal, PinBarNo3_Price, PinBarNo3_Timeを初期化して、retを返す。
//  retが、NO_SIGNALの時は、現時点から2つ前にピンバーが発生し、かつ、1つ前が大陽線または大陰線かを検証。

   int trendCloud_Shift0;
   int flag_Trend;
   
   // 
   // 現シフト０を出発点として、直近で、2つ前にピンバー、1つ前に大陽線・大陰線が発生していることを探す。
   //
   int i;
   bool flag_get_PinBarNo3_Firststep = false;
   for(i = 0; i < 100; i++) {
      flag_get_PinBarNo3_Firststep = 
      get_PinBarNo3_Firststep(mTimeFrame,
                              mShift + i,       // 計算を始めるシフト番号。このシフトの2つ前でピンバーが発生し、1つ前で大陽線・大陰線が発生していれば、true
                              PinBarNo3_Signal, // 出力：条件を満たした場合の雲の色、ピンバーの形、直後の線の値から、1～４を返す
                              PinBarNo3_Price,  // 出力：下髭の高値、または、上髭の安値 
                              PinBarNo3_Time);  // 出力：条件を達成した時間。引数mStartShiftの時間   
      if(flag_get_PinBarNo3_Firststep == true) {
         break;
      }
   }
   // 上記の探索期間中に条件を満たすピンバーと足が見つからなければ、NO_SIGNAL
   if(flag_get_PinBarNo3_Firststep == false 
      || (flag_get_PinBarNo3_Firststep == true && (PinBarNo3_Signal < 1 || PinBarNo3_Signal > 4))
       ) {
      return NO_SIGNAL;
   }
   else {
   }

   if(PinBarNo3_Time > 0 && PinBarNo3_Time <= dtNow) {  // 売買シグナルを出すためのピンバーと大陰線・陽線の組あわせが発生済み。
      if(PinBarNo3_Signal == 1) { 
         trendCloud_Shift0 =  get_TrendCloud(global_Symbol,    // 通貨ペア
                                   mTimeFrame, // 時間軸
                                   0 + mShift, // 雲の発生を判断するシフト
                                   SMA20,      // 出力：雲の発生に判断したSMA20
                                   SMA50       // 出力：雲の発生に判断したSMA50
                                  );

         flag_Trend = get_Trend_EMA_PERIODH4(0, mShift);
         if( trendCloud_Shift0 != DownTrend  // 下降トレンドの茶雲以外ならOK
            && flag_Trend == UpTrend       // １つ上が上昇トレンドであればOK
            && NormalizeDouble(iLow(global_Symbol, mTimeFrame, mShift) , global_Digits) <= NormalizeDouble(PinBarNo3_Price, global_Digits)) {  // 本来はAskだが、シフトmShift時点のAskは取得できないため、当時の最安値が下髭の高値を割り込んだかどうかを判断する。
               init_PinBarNo3Params();
               return BUY_SIGNAL;
         }
      }
      else if(PinBarNo3_Signal == 2) { 
         flag_Trend = get_Trend_EMA_PERIODH4(0, mShift);
         if(flag_Trend == UpTrend 
            && NormalizeDouble(iLow(global_Symbol, mTimeFrame, mShift) , global_Digits) <= NormalizeDouble(PinBarNo3_Price, global_Digits)) {  // 本来はAskだが、シフトmShift時点のAskは取得できないため、当時の最安値が下髭の高値を割り込んだかどうかを判断する。
            init_PinBarNo3Params();
            return BUY_SIGNAL;
         }
      }
      else if(PinBarNo3_Signal == 3) { 
         trendCloud_Shift0 =  get_TrendCloud(global_Symbol,    // 通貨ペア
                                   mTimeFrame, // 時間軸
                                   0 + mShift,     // 雲の発生を判断するシフト
                                   SMA20,    // 出力：雲の発生に判断したSMA20
                                   SMA50     // 出力：雲の発生に判断したSMA50
                                  );
         flag_Trend = get_Trend_EMA_PERIODH4(0, mShift);
         
         if(trendCloud_Shift0 == DownTrend
            && flag_Trend == DownTrend
            && NormalizeDouble(iHigh(global_Symbol, mTimeFrame, mShift), global_Digits) >= NormalizeDouble(PinBarNo3_Price, global_Digits)) {  // 本来はBidを使うが、シフトmShift時点のBidは取得できないため、当時の最高値が上髭の安値を上回ったかどうかを判断する。
               init_PinBarNo3Params();
               return SELL_SIGNAL;
         }
      }
      else if(PinBarNo3_Signal == 4) { 
         flag_Trend = get_Trend_EMA_PERIODH4(0, mShift);
         if(flag_Trend == DownTrend 
            && NormalizeDouble(iHigh(global_Symbol, mTimeFrame, mShift), global_Digits) >= NormalizeDouble(PinBarNo3_Price, global_Digits)) {  // 本来はBidを使うが、シフトmShift時点のBidは取得できないため、当時の最高値が上髭の安値を上回ったかどうかを判断する。
           init_PinBarNo3Params();
            return SELL_SIGNAL;
         }
      }
   }
  
   return NO_SIGNAL;
}



//
// 売買判定をする計算対象シフトの１つ前から順に、直近で条件を満たしているシフトを探す。
// 関数に引数渡ししたシフト、2つ前のシフトでピンバーが発生し、引数のシフト1つ前で大陽線・大陰線が発生していれば、
// PinBarNo3_Signal, PinBarNo3_Price, PinBarNo3_Timeを更新する処理。
// ①2つ前のシフトで、SMA5が水色の中にもぐり、上向き矢印ピンバー。直後がピンの高値を超える大陽線  →　PinBarSignal = 1;
// ②2つ前のシフトで、SMA5が水色の下に突き抜けて、上向き矢印ピンバー。直後がピンの高値を超える大陽線  →　PinBarSignal = 2;
// ③2つ前のシフトで、SMA5が茶色の中にもぐり、下向き矢印ピンバー。直後がピンの安値を超える大陰線 →　PinBarSignal = 3;
// ④2つ前のシフトで、SMA5が茶色の上に突き抜けて、下向き矢印ピンバー。直後がピンの安値を超える大陰線  →　PinBarSignal = 4;
bool get_PinBarNo3_Firststep(int mTimeFrame,
                             int mStartShift,        // 計算を始めるシフト番号。このシフトの2つ前でピンバーが発生し、1つ前で大陽線・大陰線が発生していれば、true
                             int &mPinBarNo3_Signal, // 出力：条件を満たした場合の雲の色、ピンバーの形、直後の線の値から、1～４を返す
                             double &mPinBarNo3_Price,// 出力：下髭の高値、または、上髭の安値 
                             datetime &mPinBarNo3_Time // 出力：条件を達成した時間。引数mStartShiftの時間
   ) {
   // ２．都度、以下を調べる。初期値は、PinBarNo3_Signal = INT_VALUE_MIN;
   // 　①2つ前のシフトで、SMA5が水色の中にもぐり、上向き矢印ピンバー。直後がピンの高値を超える大陽線  →　PinBarSignal = 1;
   // 　②2つ前のシフトで、SMA5が水色の下に突き抜けて、上向き矢印ピンバー。直後がピンの高値を超える大陽線  →　PinBarSignal = 2;
   // 　③2つ前のシフトで、SMA5が茶色の中にもぐり、下向き矢印ピンバー。直後がピンの安値を超える大陰線 →　PinBarSignal = 3;
   // 　④2つ前のシフトで、SMA5が茶色の上に突き抜けて、下向き矢印ピンバー。直後がピンの安値を超える大陰線  →　PinBarSignal = 4;
   // シフトmStartShiftにおいて、SMA20とSMA50で雲が発生しているかを判断する。
   // ・水色雲：SMA50よりSMA20が上にある上昇サイン＝UpTrendを返す=SMA20 > mSMA50
   // ・茶色雲：SMA50よりSMA20が下にある下落サイン＝DownTrendを返す=SMA20 < mSMA50
   double SMA05 = DOUBLE_VALUE_MIN;
   double SMA20 = DOUBLE_VALUE_MIN;
   double SMA50 = DOUBLE_VALUE_MIN; 
   int trendCloud = NoTrend;
      
   mPinBarNo3_Signal = INT_VALUE_MIN;
   mPinBarNo3_Price  = DOUBLE_VALUE_MIN;
   mPinBarNo3_Time   = INT_VALUE_MIN;

   trendCloud =  get_TrendCloud(global_Symbol,   // 通貨ペア
                                mTimeFrame,      // 時間軸
                                1 + mStartShift, // 雲の発生を判断するシフト
                                SMA20,           // 出力：雲の発生に判断したSMA20
                                SMA50            // 出力：雲の発生に判断したSMA50
                               );
                               
   if(trendCloud == UpTrend || trendCloud == DownTrend) {
      SMA05 = iMA( global_Symbol,     // 通貨ペア
                      mTimeFrame,  // 時間軸
                      5,           // MAの平均期間
                      0,           // MAシフト
                      MODE_SMA,    // MAの平均化メソッド
                      PRICE_CLOSE, // 適用価格
                      2 + mStartShift  // シフト
                  );

      bool flag_is_PinBar = false;
      bool flag_is_BigBody = false;
      // 2つ前が水色雲の時
      if(trendCloud == UpTrend) {
         // 2つ前に上向きピンバーが発生していれば、次が大陽線を確認する。
         flag_is_PinBar = is_PinBar(mTimeFrame, 
                                    BUY_SIGNAL, 
                                    2 + mStartShift, 
                                    PinBarPIN_MAX_PER);
         if(flag_is_PinBar == true) {
            // 1つ前が大陽線であり、2つ前の高値を抜いていれば、SMA05の位置に応じて、PinBarSignalが１，２
            flag_is_BigBody = is_BigBody(mTimeFrame, BUY_SIGNAL, 1 + mStartShift, PinBarBODY_MIN_PER);
            
            if(flag_is_BigBody == true) {

               if(NormalizeDouble(iHigh(global_Symbol, mTimeFrame, 2 + mStartShift),global_Digits) < NormalizeDouble(iHigh(global_Symbol, mTimeFrame, 1 + mStartShift), global_Digits ) ){
                  if(SMA05  >= SMA50 && SMA05 <= SMA20) {
                     mPinBarNo3_Signal = 1;
                     mPinBarNo3_Price  = iHigh(global_Symbol, mTimeFrame, 2 + mStartShift);
                     mPinBarNo3_Time   = iTime(global_Symbol, mTimeFrame, mStartShift);
                     
                     return true;
                  }
                  else if(SMA05  <= SMA50) {
                     mPinBarNo3_Signal = 2;
                     mPinBarNo3_Price  = iHigh(global_Symbol, mTimeFrame, 2 + mStartShift);
                     mPinBarNo3_Time   = iTime(global_Symbol, mTimeFrame, mStartShift);
                     
                     return true;
                  }
               }
            }
         }
      }
      // 2つ前が茶色雲の時SMA20 < mSMA50
      if(trendCloud == DownTrend) {
         // 2つ前に下向きピンバーが発生していれば、次が大陰線を確認する。
         flag_is_PinBar = is_PinBar(mTimeFrame, 
                                    SELL_SIGNAL, 
                                    2 + mStartShift, 
                                    PinBarPIN_MAX_PER);
         if(flag_is_PinBar == true) {
            // 1つ前が大陰線であり、2つ前の安値を下抜いていれば、SMA05の位置に応じて、PinBarSignalが3, 4
            flag_is_BigBody = is_BigBody(mTimeFrame, SELL_SIGNAL, 1 + mStartShift, PinBarBODY_MIN_PER);
            if(flag_is_BigBody == true) {
               if(NormalizeDouble(iLow(global_Symbol, mTimeFrame, 2 + mStartShift),global_Digits) > NormalizeDouble(iLow(global_Symbol, mTimeFrame, 1 + mStartShift), global_Digits ) ){
                  if(SMA05  >= SMA20 && SMA05 <= SMA50) {
                     mPinBarNo3_Signal = 3;
                     mPinBarNo3_Price  = iLow(global_Symbol, mTimeFrame, 2 + mStartShift);
                     mPinBarNo3_Time   = iTime(global_Symbol, mTimeFrame, mStartShift);
                     
                     return true;
                  }
                  else if(SMA05 >= SMA50) {
                     mPinBarNo3_Signal = 4;
                     mPinBarNo3_Price  = iLow(global_Symbol, mTimeFrame, 2 + mStartShift);
                     mPinBarNo3_Time   = iTime(global_Symbol, mTimeFrame, mStartShift);
                     
                     return true;
                  }
               }
            }
         }
      }
   }
   return false;
}



int entryPinBar_No5(int mShift) {
// №５：SMA50 ピンバー手法
// 本手法では便宜上SMA50よりもSMA20が上にある場合を「水色雲」とし、SMA50よりもSMA20が下にある場合は「茶色雲」とする。
// ・水色雲：SMA50よりSMA20が上にある上昇サイン
// ・茶色雲：SMA50よりSMA20が下にある下落サイン
// 
// 
// 買いの場合（1つ上の時間軸が下落でないこと）
// １．1つ前のシフトで、ローソク足が水色雲の中に潜る←ローソク足を実体部分(openとclose)とする。
// ２．同じく1つ前のシフトで、上向き矢印ピンバーが「水色雲下限」タッチ後（ピンバーのLowがSMA50を下回る）に出現する
// 　　ピンバーの高値がSMA50より下の場合は、対象外。
// ３．次の足の始値で買いエントリー
// 
// 売りの場合（1つ上の時間軸が上昇でないこと）
// １．1つ前のシフトで、ローソク足が茶色雲の中に潜る←ローソク足を実体部分(openとclose)とする。
// ２．同じく1つ前のシフトで、下向き矢印ピンバーが「茶色雲上限」タッチ後（ピンバーのHighがSMA50を上回る）に出現する
// ３．次の足の始値で売りエントリー
// 
// 利益確定
// １．エントリー後「+20pips」にリミットを設定する
// 
// 損切確定
// １．エントリー後、ピンバーの安値（買い）、高値（売り）まで10pips以下の場合「10pips」にストップを設定
// ２．ピンバー安値、ピンバーの高値までの距離が「10pips」以上離れている場合は、安値、高値から1pips余裕を見てストップを設定
   int mSignal  = NO_SIGNAL;
   int mTimeFrame = getTimeFrame(PinBarTimeframe);
      
   datetime nowDT = iTime(global_Symbol, mTimeFrame, mShift);

   int upper_TF = get_UpperLowerPeriod_ENUM_TIMEFRAMES(mTimeFrame, 1); // 1つ上の時間軸
   int flag_Trend; // 1つ上の時間軸のトレンド

   double SMA20 = DOUBLE_VALUE_MIN;
   double SMA50 = DOUBLE_VALUE_MIN;
   double open_i  = DOUBLE_VALUE_MIN;   
   double high_i  = DOUBLE_VALUE_MIN;   
   double low_i   = DOUBLE_VALUE_MIN;   
   double close_i = DOUBLE_VALUE_MIN;
   
   int trendCloud = NoTrend;
   int trendCloud_shift0 = NoTrend;

   double targetPrice = DOUBLE_VALUE_MIN; // 上向き矢印ピンバーの高値。現時点のASKがこの値以下であれば、買いを発注する。
   bool flag_is_PinBar; 
   
   // 
   // ロング
   // １．ローソク足が水色雲の中に潜る←ローソク足を実体部分(openとclose)とする。
   // ２．上向き矢印ピンバーが「水色雲下限」タッチ後（ピンバーのLowがSMA50を下回る）に出現するピンバーの高値がSMA50より下の場合は、対象外。
   // ３．次の足の始値で買いエントリー
   //
   SMA20 = DOUBLE_VALUE_MIN;
   SMA50 = DOUBLE_VALUE_MIN;
   trendCloud = get_TrendCloud(global_Symbol, mTimeFrame, 1 + mShift, SMA20, SMA50);
   // 水色の雲であること　SMA50 < SMA20
   if(trendCloud == UpTrend) { 
      // 1つ前のシフトが上向き矢印ピンバー（下髭）であること
      flag_is_PinBar = is_PinBar(mTimeFrame, 
                                 BUY_SIGNAL, 
                                 1 + mShift, 
                                 PinBarPIN_MAX_PER);
      if(flag_is_PinBar == true) {  
         // ピンバーの実体部分が、水色の雲の中にあること。また、下髭(low)が水色の雲の下の線(SMA50)を下抜けていること。
         open_i  = NormalizeDouble(iOpen(global_Symbol, mTimeFrame,  1 + mShift), global_Digits);
         close_i = NormalizeDouble(iClose(global_Symbol, mTimeFrame, 1 + mShift), global_Digits);
         low_i   = NormalizeDouble(iLow(global_Symbol, mTimeFrame,   1 + mShift), global_Digits);
         
         if(   (open_i > SMA50 && open_i < SMA20)
            && (close_i > SMA50 && close_i < SMA20)
            && (low_i < SMA50) ) {
            // 水色雲の時点で上昇トレンドのため、1つ上のトレンドを見るのは廃止、
            flag_Trend = get_Trend_EMA_PERIODH4(0, mShift);
            if(flag_Trend == UpTrend) {
               return BUY_SIGNAL;
            }
         }

      }
   }

   
   // 
   // ショート
   // １．ローソク足が茶色雲の中に潜る←ローソク足を実体部分(openとclose)とする。
   // ２．下向き矢印ピンバーが「茶色雲上限」タッチ後（ピンバーのHighがSMA50を上回る）に出現する
   // ３．次の足の始値で売りエントリー
   //
   // 茶色の雲であること　SMA50 > SMA20
   else if(trendCloud == DownTrend) { 
      // 1つ前のシフトが下向き矢印ピンバー（上髭）であること
      flag_is_PinBar = is_PinBar(mTimeFrame, 
                                 SELL_SIGNAL, 
                                 1 + mShift, 
                                 PinBarPIN_MAX_PER);
      if(flag_is_PinBar == true) {  
         // ピンバーの実体部分が、水色の雲の中にあること。また、下髭(low)が水色の雲の下の線(SMA50)を下抜けていること。
         open_i  = NormalizeDouble(iOpen(global_Symbol, mTimeFrame,  1 + mShift), global_Digits);
         close_i = NormalizeDouble(iClose(global_Symbol, mTimeFrame, 1 + mShift), global_Digits);
         high_i  = NormalizeDouble(iHigh(global_Symbol, mTimeFrame,   1 + mShift), global_Digits);
         if((open_i < SMA50 && open_i > SMA20)     // ローソク足のOpen側が雲の中
            && (close_i < SMA50 && close_i > SMA20)// ローソク足のClose側が雲の中
            && (high_i > SMA50)                    // 上髭が、雲の天井を突破
            ) {
            // 茶色雲の時点で下降トレンドのため、1つ上のトレンドを見るのは廃止、
            flag_Trend = get_Trend_EMA_PERIODH4(0);
            if(flag_Trend == DownTrend) {
               return SELL_SIGNAL;
            }
         }

      }
   }
   else {
      // 雲が水色でも茶色でもないときは、何もしない。
   } 
   
   return NO_SIGNAL;
}	







/////////////////////////////////////////////////////////////////////////
////////////////////////////Puer_PinBAR.mqhからコピー ここまで///////////////////
/////////////////////////////////////////////////////////////////////////



/////////////////////////////////////////////////////////////////////////
////////////////////////////Puer_RandomTrade.mqhからコピー///////////////////
/////////////////////////////////////////////////////////////////////////


int entryRT_only_Rand() {

   double randomValue = (double)(MathRand() % 3); // MathRandが、0～32767の整数を返す。
   

   // 乱数%3が、0ならば売り
   if(randomValue == 0) {
      return SELL_SIGNAL;
   }
   // 乱数%3が、1ならば買い
   else if(randomValue == 1) {
      return BUY_SIGNAL;
   }
   // 乱数%3が、2ならば様子見
   else if(randomValue == 2) {
      return NO_SIGNAL;
   }
   // 乱数%3が、0-2以外ならば様子見
   else  {
      return NO_SIGNAL;
   }
   
   return NO_SIGNAL;
}



/////////////////////////////////////////////////////////////////////////
////////////////////////////Puer_RandomTrade.mqhからコピー ここまで//////////////
/////////////////////////////////////////////////////////////////////////


/////////////////////////////////////////////////////////////////////////
////////////////////////////Tigris_COMMON.mqhからコピー /////////////////
/////////////////////////////////////////////////////////////////////////
// ENUM_TIMEFRAMES型データ（PERIOD_M1～PERIOD_MN1）を１～９に割り当て。
int    PERIOD_00_INT  = 0;   // ENUM_TIMEFRAMES:PERIOD_CURRENTの整数値
int    PERIOD_M1_INT  = 1;   // ENUM_TIMEFRAMES:PERIOD_M1の整数値
int    PERIOD_M5_INT  = 2;   // ENUM_TIMEFRAMES:PERIOD_M5の整数値
int    PERIOD_M15_INT = 3;   // ENUM_TIMEFRAMES:PERIOD_M15の整数値
int    PERIOD_M30_INT = 4;   // ENUM_TIMEFRAMES:PERIOD_M30の整数値
int    PERIOD_H1_INT =  5;   // ENUM_TIMEFRAMES:PERIOD_H1の整数値
int    PERIOD_H4_INT =  6;   // ENUM_TIMEFRAMES:PERIOD_H4の整数値
int    PERIOD_D1_INT =  7;   // ENUM_TIMEFRAMES:PERIOD_D1の整数値
int    PERIOD_W1_INT =  8;   // ENUM_TIMEFRAMES:PERIOD_W1の整数値
int    PERIOD_MN1_INT = 9;   // ENUM_TIMEFRAMES:PERIOD_MN1の整数値
int    PERIOD_MINOVER_INT = INT_VALUE_MIN;// ENUM_TIMEFRAMES:PERIOD_M1より下を指す時のエラー値
int    PERIOD_MAXOVER_INT = INT_VALUE_MAX;// ENUM_TIMEFRAMES:PERIOD_MN1より上を指す時のエラー値


int getTimeFrame(int tfIndex) {
// ストラテジーテスターで、時間軸を変更したテストを行えるように、tfIndexは、0から9までの値とする。
// この関数は、tfIndexを、ENUM_TIMEFRAMES(PERIOD_M1 = 1, PERIOD_M5 = 5など）に変換する。
// tfIndexが、0から9までのいずれとも一致しない場合は、PERIOD_MINOVER_INTを返す。
   int buf = Period();
   switch(tfIndex) {
      case 0:
   		return buf;
   		break;
      
      case 1:
   		return PERIOD_M1;
		   break;

      case 2:
		   return PERIOD_M5;
		   break;

      case 3:
		   return PERIOD_M15;
		   break;

      case 4:
		   return PERIOD_M30;
		   break;

      case 5:
		   return PERIOD_H1;
		   break;

      case 6:
		   return PERIOD_H4;
		   break;

      case 7:
		   return PERIOD_D1;
		   break;

      case 8:
		   return PERIOD_W1;
		   break;

      case 9:
		   return PERIOD_MN1;
		   break;

      default:
		   return INT_VALUE_MIN;
		   break;
    }
    
   return PERIOD_MINOVER_INT;
}


// 引数mCurrTFで渡した時間軸（ENUM_TIMEFRAMES型)に対して、
// 引数mUpperLowerで渡しただけ上か下の時間軸（ENUM_TIMEFRAMES型)を返す
// 【注意】
// ・引数も返り値もENUM_TIMEFRAMES型。
int get_UpperLowerPeriod_ENUM_TIMEFRAMES(int mCurrENUM_TIMEFRAMES,    //　現在の時間軸。ENUM_TIMEFRAMESのPERIOD_M1～PERIOD_MN1
                                         int mUpperLower // いくつ上下の時間軸を返すか。1つ上ならば+1、1つ下ならば-1
   ) {                                
   int ret_ENUM_TIMEFRAMES = -1; // 返り値
   int currTF = getTimeFrameReverse(mCurrENUM_TIMEFRAMES); //引数にPERIOD_M1を渡せば1, PERIOD_M５を渡せば2を返す。返す範囲は、1～9まで。
   ret_ENUM_TIMEFRAMES = getTimeFrame(currTF + 1);
   bool flag = checkTimeFrame(ret_ENUM_TIMEFRAMES);
   if(flag == true) {
      return ret_ENUM_TIMEFRAMES;
   }
   else {
      return PERIOD_MINOVER_INT;
   }
}


// ピンバーが発生していればtrueを返す。
// 始値と終値で形成される実線が陰線でも陽線でも可とする。
bool is_PinBar(int    mTimeFrame,       // 計算用時間軸
               int    mSignal,          // 下髭のPinBARを探す時は、BUY_SIGNAL。上髭を探す時は、SELL_SIGNAL
               int    mShift,           // 何本前のシフトがPinBarを形成しているか
               double mPinBarPIN_MAX_PER) { // 実体部分(始値と終値の差）が最高値と最安値の何％以下ならPinBARとみなすか

   double close_i = DOUBLE_VALUE_MIN;
   double open_i  = DOUBLE_VALUE_MIN;
   double high_i  = DOUBLE_VALUE_MIN;
   double low_i   = DOUBLE_VALUE_MIN;

   double down_div = DOUBLE_VALUE_MIN; // 下髭部分の長さ
   double up_div   = DOUBLE_VALUE_MIN; // 上髭部分の長さ
   
   double body_Size = DOUBLE_VALUE_MIN;
   
   close_i = NormalizeDouble(iClose(global_Symbol, mTimeFrame, mShift), global_Digits);    
   open_i  = NormalizeDouble(iOpen(global_Symbol, mTimeFrame, mShift) , global_Digits);
   high_i  = NormalizeDouble(iHigh(global_Symbol, mTimeFrame, mShift) , global_Digits); 
   low_i   = NormalizeDouble(iLow(global_Symbol, mTimeFrame, mShift)  , global_Digits);

   // 上髭の長さ＝CloseとOpenの高い方と、高値との差分
   if(close_i >= open_i) {
      up_div = high_i - close_i;
   }
   else {
      up_div = high_i - open_i;
   }
   // 下髭の長さ＝CloseとOpenの低い方と、安値との差分
   if(close_i >= open_i) {
      down_div = open_i - low_i;
   }
   else {
      down_div = close_i - low_i;
   }

   // 上髭が長い場合
   if(up_div > 0.0
      && up_div >= down_div) {
      // 実体の長さが、上髭のmPinBarPIN_MAX_PER％未満ならピン
      body_Size = MathAbs(open_i - close_i);
      if(body_Size / up_div * 100.0 < mPinBarPIN_MAX_PER) {
         // 上髭ピンが見つかった
         if(mSignal == BUY_SIGNAL) {  // 下髭ピンを探そうとしていたのでfalseを返す。
            return false;
         }
         else {
            return true;
         }
      }
   }
   //　下髭が長い場合
   else if(down_div > 0.0 
      && up_div <= down_div) {
      // 実体の長さが、下髭のmPinBarPIN_MAX_PER％未満ならピン
      body_Size = MathAbs(open_i - close_i);
      
      if(body_Size / down_div * 100.0 < mPinBarPIN_MAX_PER) {
         // 下髭ピンが見つかった
         if(mSignal == SELL_SIGNAL) {
            return false;
         }
         else {
            return true;
         }
      }
   }
   // 髭の長さが同じ場合
   else {
      return false;
   }

   return false;
}


// 1つ手前のシフトからEMAを取得して、EMAを結ぶ回帰直線の傾きでトレンドを分析する。
int get_Trend_EMA_PERIODH4(int mTF) {  // 旧名称get_Trend_EMA
   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、NoTrendとする。
   if(mTF < PERIOD_CURRENT || mTF > PERIOD_MN1) {
      return NoTrend;
   }

   double EMA_1 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,1), global_Digits);
   double EMA_2 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,2), global_Digits);	
   double EMA_3 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,3), global_Digits);	
   double EMA_4 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,4), global_Digits);	
   double EMA_5 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,5), global_Digits);	
	
   double data[5];
   ArrayInitialize(data, 0.0);
   data[0] = EMA_5;  // 配列に古い順に代入
   data[1] = EMA_4;
   data[2] = EMA_3;
   data[2] = EMA_2;
   data[2] = EMA_1;

   double slope     = DOUBLE_VALUE_MIN;
   double intercept = DOUBLE_VALUE_MIN; 
   // 候補が、配列に古い順に入っているので、傾きslopeをそのまま使うことができる。

/*printf("[%d]COMM トレンド判断get_Trend_EMA %s 時間軸=%d シフト3==%s=%s シフト2==%s=%s シフト1==%s=%s", __LINE__,
            TimeToStr(Time[0]),
            mTF,
            TimeToStr(iTime(global_Symbol,mTF, 3)), DoubleToStr(data[0], global_Digits),
            TimeToStr(iTime(global_Symbol,mTF, 2)),DoubleToStr(data[1], global_Digits),
            TimeToStr(iTime(global_Symbol,mTF, 1)),DoubleToStr(data[2], global_Digits));
*/
   bool flag =  calcRegressionLine(data, 5, slope, intercept);
//printf("[%d]COMM トレンド判断calcRegressionLine=%s", __LINE__,DoubleToStr(slope, global_Digits));

   if(flag == false) {
      return NoTrend;
   }
   else {
      if(slope > 0.0) {
//printf("[%d]COMM UPTREND", __LINE__);

         return UpTrend;
      }
      else if(slope < 0.0) {
//printf("[%d]COMM DOWNTREND", __LINE__);
         return DownTrend;
      }
      else {
//printf("[%d]COMM トレンド無し", __LINE__);
      
         return NoTrend;
      }
   }
   return NoTrend;
}


// getTimeFrameの逆。
// 引数にPERIOD_M1を渡せば1, PERIOD_M５を渡せば2,PERIOD_M15を渡せば3を返す。
//　引数にPERIOD_MN1を渡した時に9を返すのが最大。
int getTimeFrameReverse(int tfIndex) {
// ストラテジーテスターで、時間軸を変更したテストを行えるように、tfIndexは、0から9までの値とする。
// この関数は、ENUM_TIMEFRAMES(PERIOD_M1 = 1, PERIOD_M5 = 5など）を0から9までに変換する。
// tfIndexが、0から9までのいずれとも一致しない場合は、PERIOD_CURRENTを返す。
   switch(tfIndex) {
      case PERIOD_CURRENT:
   		return PERIOD_00_INT;
   		break;
      
      case PERIOD_M1:
   		return PERIOD_M1_INT;
		   break;

      case PERIOD_M5:
		   return PERIOD_M5_INT;
		   break;

      case PERIOD_M15:
		   return PERIOD_M15_INT;
		   break;

      case PERIOD_M30:
		   return PERIOD_M30_INT;
		   break;

      case PERIOD_H1:
		   return PERIOD_H1_INT;
		   break;

      case PERIOD_H4:
		   return PERIOD_H4_INT;
		   break;

      case PERIOD_D1:
		   return PERIOD_D1_INT;
		   break;

      case PERIOD_W1:
		   return PERIOD_W1_INT;
		   break;

      case PERIOD_MN1:
		   return PERIOD_MN1_INT;
		   break;

      default:
		   return PERIOD_00_INT;
		   break;
    }
    
    return 0;
}


//+------------------------------------------------------------------+
//|   TimeFrameの正当性をチェックする                                |
//+------------------------------------------------------------------+
bool checkTimeFrame(int tf) {
   switch(tf) {
      case PERIOD_CURRENT:
      case PERIOD_M1:
      case PERIOD_M5:
      case PERIOD_M15:
      case PERIOD_M30:
      case PERIOD_H1:
      case PERIOD_H4:
      case PERIOD_D1:
      case PERIOD_W1:
      case PERIOD_MN1:        
	      return true;
         break;
      default:
         return false;
         break;
    }
    return false;
}
/////////////////////////////////////////////////////////////////////////
////////////////////////////Tigris_COMMON.mqhからコピー ここまで/////////////////
/////////////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////////////
////////////////////////////Puer_RVI.mqhからコピー /////////////////
/////////////////////////////////////////////////////////////////////////


//+------------------------------------------------------------------+
//|95.RVI                                                 　　　   |
//+------------------------------------------------------------------+
double Sigma2_Min_Width_POINT = 0.05; // ±2σの最小幅
int    average_period   = 7;   //RVIの平均計算期間

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



/////////////////////////////////////////////////////////////////////////
////////////////////////////Puer_RVI.mqhからコピー ここまで/////////////////
/////////////////////////////////////////////////////////////////////////





/////////////////////////////////////////////////////////////////////////
////////////////////////////Tigris_TradingLine.mqhからコピー /////////////////
/////////////////////////////////////////////////////////////////////////
// トレーディングライン
double   g_past_max     = DOUBLE_VALUE_MIN; // 過去の最高値
datetime g_past_maxTime = -1;               // 過去の最高値の時間
double   g_past_min     = DOUBLE_VALUE_MIN; // 過去の最安値
datetime g_past_minTime = -1;               // 過去の最安値の時間
double   g_past_width   = DOUBLE_VALUE_MIN; // 過去値幅。past_max - past_min
double   g_long_Min     = DOUBLE_VALUE_MIN; // ロング取引を許可する最小値
double   g_long_Max     = DOUBLE_VALUE_MIN; // ロング取引を許可する最大値
double   g_short_Min    = DOUBLE_VALUE_MIN; // ショート取引を許可する最小値
double   g_short_Max    = DOUBLE_VALUE_MIN; // ショート取引を許可する最大値
//+------------------------------------------------------------------+
//|   取引の可否を意味する境界を計算する。  計算開始位置をシフト0以外にするときは、別関数を使う|
//+------------------------------------------------------------------+
// 旧名称get_TradingLines
bool calc_TradingLines(string  mSymbol,        // 通貨ペア
                       int      mTimeframe,     // 計算に使う時間軸
                       int      mShiftSize,     // 計算対象にするシフト数。何シフト前までさかのぼって、最大、最小を求めるか。
                       double   &mPast_max,     // 出力：過去の最高値
                       datetime &mPast_maxTime, // 出力：過去の最高値の時間
                       double   &mPast_min,     // 出力：過去の最安値
                       datetime &mPast_minTime, // 出力：過去の最安値の時間
                       double   &mPast_width,   // 出力：過去値幅。past_max - past_min
                       double   &mLong_Min,     // 出力：ロング取引を許可する最小値
                       double   &mLong_Max,     // 出力：ロング取引を許可する最大値
                       double   &mShort_Min,    // 出力：ショート取引を許可する最小値
                       double   &mShort_Max     // 出力：ショート取引を許可する最大値
                       ) {
   int mIndex = 0;
   
   mIndex = iHighest(    // 指定した通貨ペア・時間軸の最高値インデックスを取得
             mSymbol,    // 通貨ペア
             mTimeframe, // 時間軸 
             MODE_HIGH,  // データタイプ[高値を指定]
             mShiftSize, // 検索カウント。時間軸TIME_FRAME1TO9をSHIFT_SIZE個参照する。
             0           // 開始インデックス。高値更新を繰り返した場合を考えて、0番目のバーも計算に含める
   );
      
   if(mIndex >= 0) {
      mPast_max = iHigh(         // 指定した通貨ペア・時間軸の高値を取得
                     mSymbol,    // 通貨ペア
                     mTimeframe, // 時間軸 
                     mIndex      // インデックス[iHighestで取得したインデックスを指定]
      );
      mPast_maxTime = iTime(mSymbol, mTimeframe, mIndex);
   }
   else {
      return false;
   }
   
   mIndex = 0;
   mIndex = iLowest(             // 指定した通貨ペア・時間軸の最高値インデックスを取得
                    mSymbol,     // 通貨ペア
                    mTimeframe,  // 時間軸 
                    MODE_LOW,    // データタイプ[安値を指定]
                    mShiftSize,  // 検索カウント。時間軸TIME_FRAME1TO9をSHIFT_SIZE個参照する。
                    0            // 開始インデックス。安値更新を繰り返した場合を考えて、0番目のバーも計算に含める
   );

   
   if(mIndex >= 0) {
      mPast_min = iLow(            // 指定した通貨ペア・時間軸の高値を取得
                       mSymbol,    // 通貨ペア
                       mTimeframe, // 時間軸 
                       mIndex      // インデックス[iHighestで取得したインデックスを指定]
                     );
      mPast_minTime = iTime(mSymbol, mTimeframe, mIndex);
   }
   else {                
      return false;
   }   

   if(mPast_min <= 0.0 && mPast_max <= 0.0) {
      return false;   
   }

   if(NormalizeDouble(mPast_min, global_Digits) > NormalizeDouble(mPast_max, global_Digits)) {
      return false;   
   }

   //過去値幅past_widthを、最高値past_max - 最安値past_minとする。
   mPast_width = NormalizeDouble(mPast_max - mPast_min, global_Digits);

//
//ロング取引及びショート取引を許可する価格帯をグローバル変数に設定する。 
//気配値が、上限または下限に近いときは、新規取引はしない
//past_width = past_max - past_min
//mShort_Max----------------------------------------------------- past_max
//             → SHORT_ENTRY_WIDTH_PER (ショート実行可能)          ↓
//mShort_Min-----------------------------------------------------   ↓
//　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　↓
//　　　　　　　　　　　取引不能　　　　　　　　　　　　　　　　　mPast_width
//                　　　　　　　　　　　　　　　　　　　　　　　　  ↑
//mLong_Max -----------------------------------------------------   ↑
//             → LONG_ENTRY_WIDTH_PER (ロング実行可能)             ↑
//mLomg_Min------------------------------------------------------ past_min


   // 現在値が、過去最高値から、過去最安値と最高値の価格帯のEXCLUDE_LOWER_PER％下をショート上限とする。
   mShort_Max = mPast_max;
   // 現在値が、過去最高値から、過去最安値と最高値の価格帯のSHORT_ENTRY_WIDTH_PER％下をロング下限とする。
   mShort_Min = mPast_max - mPast_width * SHORT_ENTRY_WIDTH_PER / 100.0; 
   // 現在値が、過去最安値から、過去最安値と最高値の価格帯のLONG_ENTRY_WIDTH_PER％上をロング上限とする。
   mLong_Max =  mPast_min + mPast_width * LONG_ENTRY_WIDTH_PER / 100.0; 
   // 現在値が、過去最安値から、過去最安値と最高値の価格帯のEXCLUDE_LOWER_PER％上をロング下限とする。
   mLong_Min =  mPast_min;
/*printf( "[%d]COM シフトを渡さない関数>%s< mLong_Max%s =  mPast_min%s + mPast_width%s * LONG_ENTRY_WIDTH_PER%s / 100.0;" , __LINE__, TimeToStr(Time[0]), 
                      DoubleToStr(mLong_Max, global_Digits),
                      DoubleToStr(mPast_min, global_Digits),
                      DoubleToStr(mPast_width, global_Digits),
                      DoubleToStr(LONG_ENTRY_WIDTH_PER, global_Digits)
);*/

   if(IsTesting() == true) {
      // バックテスト時は、描画処理をしない。
   }
   else {
      // ロング上限に線を引く
      ObjectDelete("Long_Max");
      ObjectCreate("Long_Max",OBJ_HLINE,0,0,mLong_Max);
      ObjectSet("Long_Max",OBJPROP_COLOR,clrLime);
      ObjectSet("Long_Max",OBJPROP_WIDTH,3);
      ObjectSet("Long_Max", OBJPROP_STYLE, STYLE_DOT);
      ObjectSet("Long_Max",OBJPROP_FONTSIZE      ,20);         // フォントサイズ
      ObjectSetString(0,"Long_Max" ,OBJPROP_FONT ,"ＭＳ　ゴシック"); // フォントタイプ
      ObjectSetString(0,"Long_Max" ,OBJPROP_TEXT ,"ロング最大値"); // 表示する文字
      
      // ロング下限に線を引く
      ObjectDelete("Long_Min");
      ObjectCreate("Long_Min",OBJ_HLINE,0,0,mLong_Min);
      ObjectSet("Long_Min",OBJPROP_COLOR,clrLime);
      ObjectSet("Long_Min",OBJPROP_WIDTH,3);
      ObjectSet("Long_Min",OBJPROP_FONTSIZE      ,20);         // フォントサイズ
      ObjectSetString(0,"Long_Min" ,OBJPROP_FONT ,"ＭＳ　ゴシック"); // フォントタイプ
      ObjectSetString(0,"Long_Min" ,OBJPROP_TEXT ,"ロング最小値"); // 表示する文字
     
      // ショート上限に線を引く
      ObjectDelete("Short_Max");
      ObjectCreate("Short_Max",OBJ_HLINE,0,0,mShort_Max);
      ObjectSet("Short_Max",OBJPROP_COLOR,clrMediumVioletRed);
      ObjectSet("Short_Max",OBJPROP_WIDTH,3);
      ObjectSet("Short_Max",OBJPROP_FONTSIZE      ,20);         // フォントサイズ
      ObjectSetString(0,"Short_Max" ,OBJPROP_FONT ,"ＭＳ　ゴシック"); // フォントタイプ
      ObjectSetString(0,"Short_Max" ,OBJPROP_TEXT ,"ショート最大値"); // 表示する文字
      
      // ショート下限に線を引く
      ObjectDelete("Short_Min");
      ObjectCreate("Short_Min",OBJ_HLINE,0,0,mShort_Min);
      ObjectSet("Short_Min",OBJPROP_COLOR,clrMediumVioletRed);
      ObjectSet("Short_Min",OBJPROP_WIDTH,3);   
      ObjectSet("Short_Min", OBJPROP_STYLE, STYLE_DOT);
      ObjectSet("Short_Min",OBJPROP_FONTSIZE      ,20);         // フォントサイズ
      ObjectSetString(0,"Short_Min" ,OBJPROP_FONT ,"ＭＳ　ゴシック"); // フォントタイプ
      ObjectSetString(0,"Short_Min" ,OBJPROP_TEXT ,"ショート最小値"); // 表示する文字


   }
   
   return true;
}



/////////////////////////////////////////////////////////////////////////
////////////////////////////Tigris_TradingLine.mqhからコピー ここまで/////////////////
/////////////////////////////////////////////////////////////////////////



