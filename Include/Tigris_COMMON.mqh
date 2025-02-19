// 20220411 2種類のget_Trend_EMAで、トレンド判定を値の比較から回帰直線の傾きに変更した。
#include <Tigris_GLOBALS.mqh>

//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	
#define URL "http://nenshuuha.blog.fc2.com/"      //URL			
#define ERR_TITLE1 "パラメーターエラー"    //エラータイトル(その1)			
#define BUY_SIGNAL        1                //エントリーシグナル(ロング)	
#define SELL_SIGNAL      -1                //エントリーシグナル(ショート)
#define NO_SIGNAL         0                //エントリーシグナル(ロング、ショートいずれでもない)
#define MAILTIME          30

#define FINISH_CORRECT    1
#define ERROR            -997
#define ERROR_MARGINSHORT -996
#define ERROR_ORDERSEND  -1
#define ERROR_ORDERMODIFY -2
#define ERROR_ORDERSEND_TRADELINE -11

#define LINE_COLOR_LONG Blue
#define LINE_COLOR_SHORT Red
#define LINE_COLOR_CLOSE Violet
#define LINE_COLOR_DEFAULT Yellow
#define MAX_TRADE_NUM    10000  // メモリ上に読み出す実取引の最大数
#define SHIFT_LENGTH_MAX 900    // シフトの最大値。テスト時に1000シフト以上前のデータを取得できないことから、余裕を持った値とする。

#define FRAC_NUMBER  100 // メモリに持つフラクタルの総数
#define FRAC_MOUNT   1   // フラクタルの山
#define FRAC_BOTTOM -1   // フラクタルの谷
#define FRAC_NONE    0   // フラクタルの山、谷の判断不能

#define ZIGZAG_MOUNT   1
#define ZIGZAG_BOTTOM -1
#define ZIGZAG_NONE    0
#define MAX_ARRAY_NUM 10000
//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	


// オープン中の取引
int    OpenTrade_BuySell[MAX_TRADE_NUM];
double OpenTrade_OpenPrice[MAX_TRADE_NUM];
int    OpenTrade_Tick[MAX_TRADE_NUM];



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

int OPEN_PRICE  = 1;
int HIGH_PRICE  = 2;
int LOW_PRICE   = 3;
int CLOSE_PRICE = 4;      

int    UpTrend   =  1; //上昇トレンド
int    DownTrend = -1; //下降トレンド
int    NoTrend   =  0; //トレンド無し
string MachineName = AccountServer();
bool   ShowTestMsg = false; // trueの時、テストメッセージを表示する。
bool   FILEIOFLAG  = false; // trueの時、ファイル出力処理をする。



string g_StratName01 = "01FRAC";
string g_StratName04 = "04BB";
string g_StratName07 = "07STOCEMA";
string g_StratName08 = "08WPR";
string g_StratName10 = "10GMMA";
string g_StratName11 = "11KAIRI";
string g_StratName12 = "12SAR";
string g_StratName14 = "14RSIMACD";
string g_StratName15 = "15MACDRCI";
string g_StratName16 = "16Ichi";
string g_StratName17 = "17KAGI";
string g_StratName18 = "18CORR";
string g_StratName19 = "19MS";
string g_StratName20 = "20TBB";
string g_StratName21 = "21RCISWING";
string g_StratName22 = "22STAT";
string g_StratName23 = "23ADXMA";
string g_StratName24 = "24ZZ";
string g_StratName25 = "25PIN";
string g_StratName95 = "95RVI";
string g_StratName99 = "99RT";

/*
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
*/

// 描画制御
bool global_IsTesting    = false; //テストモードの時にtrue
bool global_IsVisualMode = false;//ビジュアルモードの時にtrue


// 価格4値を保持するための構造体
struct st_Pricedata {   
   string   symbol;
   int      timeframe;
   datetime dt;
   string   dtStr;
   double   open;
   double   high;
   double   low;
   double   close;
   double   volume;
};


//フラクタル計算結果を保持するための構造体。
struct st_Fractal {
   int      type;     // 山か谷か。FRAC_MOUNT、FRAC_BOTTOM、FRAC_NONE
   double   value;    // フラクタルの値
   int      shift;    // フラクタル発生時のシフト番号
   datetime calcTime; // PERIOD_M1を用いて計算したフラクタル（山）発生時刻 
};
st_Fractal st_Fractals[FRAC_NUMBER];

//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
extern string BASIC_Title="---取引時基本情報---";
extern double LOTS                = 0.01;// ロット数。1ロット=100000通貨						
extern int    SLIPPAGE            = 200; // スリッページ	
extern double MAX_SPREAD_PIPS     = 200; // スプレッドがこの値以上の時は新規取引しない。
// extern int    PING_WEIGHT_MINS    = 0; // 0～9。1:PERIOD_M1, 2:PERIOD_M5, 3:PERIOD_M15
// extern int    VTRADEBACKSHIFTNUM  = 2000;  //過去500シフトで仮想取引が発生すれば登録する。

extern string TP_SLTitle="---利確、損切PIPS数---";
extern double TP_PIPS      = 100.0;    // 1約定あたりの利確pips数。負の時は、利確値の設定や強制利確をしない。
extern double SL_PIPS      = 100.0;    // 1約定当たりの損切pips数。SL_PIPS_PER設定時は上書きされる。負の時は、損切値の設定や強制損切をしない。
extern double SL_PIPS_PER  = -5; // TP_PIPSに対するSL_PPIPSの割りあい。SL_PIPSを上書きする。負の時は、上書きしない。
// extern double RISK_PERCENT = 0.0; // 許容するリスク。2の場合、2%の損切リスクを踏まえた最大ロット数を計算する。
extern string FLOORINGTitle="---損切値の自動設定---";
extern double FLOORING          = -1.0;   // 損切値を、オープンから指定した値(PIP)の位置に変更する。PIPS数。 // 負の数の場合は、何もしない。            
extern bool   FLOORING_CONTINUE = false; // trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。    
                                             //1:PERIOD_M1, 2:PERIOD_M5, 3:PERIOD_M15, 4:PERIOD_M30, 5:PERIOD_H1, 6:PERIOD_H4
                                             //7:PERIOD_D1, 8:PERIOD_W1, 9:PERIOD_MN1
/*
extern string TRADABLELINESTitle="---取引可能な領域の計算---";
extern int    TIME_FRAME_MAXMIN     = 2;     // 1～9最高値、最安値の参照期間の単位。
                                             //1:PERIOD_M1, 2:PERIOD_M5, 3:PERIOD_M15, 4:PERIOD_M30, 5:PERIOD_H1, 6:PERIOD_H4
                                             //7:PERIOD_D1, 8:PERIOD_W1, 9:PERIOD_MN1
extern int    SHIFT_SIZE_MAXMIN     = 120;   // 最高値、最安値の参照期間
extern double ENTRY_WIDTH_PIPS      = 0.05;  // エントリーする間隔。PIPS数。
extern double SHORT_ENTRY_WIDTH_PER = 100.0; // ショート実施帯域。過去最高値から何パーセント下までショートするか
extern double LONG_ENTRY_WIDTH_PER  = 100.0; // ロング実施帯域。過去最安値から何パーセント上までロングするか
extern double ALLOWABLE_DIFF_PER    = 0.0;   // 使わない場合は、0。価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値とみなすか。 （約定間隔ENTRY_WIDTH_PIPS20pips*許容誤差ALLOWABLE_DIFF_PER10%なら差が2PIPSまでは同じ約定値）
*/

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|   共通関数                                                    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|   外部パラメーターに不適切な値が設定されていれば、falseを返す                                              |
//+------------------------------------------------------------------+
bool checkExternalParamCOMMON() {
/*
   if(FLOORING < 0) { 
      printf( "[%d]COMMエラー 外部パラメーター（共通項目）のうち、FLOORING>%d<は、正でなくてはならない。" , __LINE__, FLOORING);
      return false;
   }
*/
   
   return true;
}



//+------------------------------------------------------------------+
//|  0～9に対応するENUM_TIMEFRAMES値を返す                                 |
//+------------------------------------------------------------------+
int getTimeFrame(int tfIndex) {
// ストラテジーテスターで、時間軸を変更したテストを行えるように、tfIndexは、0から9までの値とする。
// この関数は、tfIndexを、ENUM_TIMEFRAMES(PERIOD_M1 = 1, PERIOD_M5 = 5など）に変換する。
// tfIndexが、0から9までのいずれとも一致しない場合は、PERIOD_MINOVER_INTを返す。

   switch(tfIndex) {
      case 0:
   		return PERIOD_CURRENT;
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
    
   return PERIOD_CURRENT;
}

// getTimeFrameの逆。
// 引数にPERIOD_M1を渡せば1, PERIOD_M５を渡せば2,PERIOD_M15を渡せば3を返す。
//　引数にPERIOD_MN1を渡した時に9を返すのが最大。
int getTimeFrameReverse(int tfIndex) {
// ストラテジーテスターで、時間軸を変更したテストを行えるように、tfIndexは、0から9までの値とする。
// この関数は、ENUM_TIMEFRAMES(PERIOD_M1 = 1, PERIOD_M5 = 5など）を0から9までに変換する。
// tfIndexが、0から9までのいずれとも一致しない場合は、PERIOD_CURRENTを返す。
   if(tfIndex == PERIOD_CURRENT) {
      tfIndex = Period();
   }
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
//|   TimeFrameの時間間隔を返す                                              |
//+------------------------------------------------------------------+
datetime getTimeFrameSPAN(int tfIndex) {
// ストラテジーテスターで、時間軸を変更したテストを行えるように、tfIndexは、0から9までの値とする。
// この関数は、タイムフレームtfIndexの1つの期間が、datetimeでいくつかに変換する。
// tfIndexが、いずれとも一致しない場合は、0を返す。
   switch(tfIndex) {
      case PERIOD_M1:
      case PERIOD_M5:
      case PERIOD_M15:
      case PERIOD_M30:
      case PERIOD_H1:
      case PERIOD_H4:
      case PERIOD_D1:
      case PERIOD_W1:
      case PERIOD_MN1:
         return MathAbs(iTime(global_Symbol, tfIndex, 1) - iTime(global_Symbol, tfIndex, 2));
		   break;

      default:
		   return 0;
		   break;
    }
    
    return 0;
}




//+------------------------------------------------------------------+
//| 通貨ペア別調整係数の計算                           　　      |
//+------------------------------------------------------------------+
double AdjustPoint(string Currency)  {
int SymbolDigits = (int)MarketInfo(Currency, MODE_DIGITS);
double CalculatedPoint = 0.0;

if(SymbolDigits == 2 || SymbolDigits == 3) {
    CalculatedPoint = 0.01;
}
else if(SymbolDigits  == 4 || SymbolDigits == 5) {
   CalculatedPoint = 0.0001;
}
return(CalculatedPoint);
}


//二つの価格差Pips
double get_Pips(double mPrice1,double mPrice2){
/*
https://min-fx.jp/start/fx-pips/
米ドル/円やクロス円（ユーロ/円、ポンド/円など）の場合
1pip＝0.01円（1銭）
10 pips＝0.1円（10銭）
100 pips＝1円（100銭）

一方、ユーロ/ドルやポンド/ドルなどの米ドルストレート通貨の場合、1pip＝0.0001ドル（0.01セント）
を表しています。ユーロ/ドルのレートが1.1500ドルから1.1505ドルに上昇した場合も、5pips上昇したと言うことになります。

米ドルストレート（ユーロ/ドル、ポンド/ドルなど）の場合
1pip＝0.0001ドル（0.01セント）
10pip＝0.001ドル（0.1セント）
100pip＝0.01ドル（1セント）
*/
   double ret = 0.0;
   ret = MathAbs(mPrice1 - mPrice2);
   if(global_Digits == 2 || global_Digits == 3){
      ret *= 100.0;
   }else if(global_Digits == 4 || global_Digits == 5){
      ret *= 10000.0;
   }
   return(ret);
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
double change_Point2PIPS(string mSymbol, // 関数内では使わない。MT5の同じ名前の関数との変数を合わせるためだけに存在する
                         double mPoint) {
   // 
   double ret = 0.0;
   double local_digits = Digits();
   ret = mPoint;
   if(local_digits == 2 || local_digits == 3){
      ret *= 100.0;
   }else if(local_digits == 4 || local_digits == 5){
      ret *= 10000.0;
   }
   return(ret);

}
double change_PiPS2Point(double mPips) {
/*
https://min-fx.jp/start/fx-pips/
米ドル/円やクロス円（ユーロ/円、ポンド/円など）の場合
1pip＝0.01円（1銭）
10 pips＝0.1円（10銭）
100 pips＝1円（100銭）

一方、ユーロ/ドルやポンド/ドルなどの米ドルストレート通貨の場合、1pip＝0.0001ドル（0.01セント）
を表しています。ユーロ/ドルのレートが1.1500ドルから1.1505ドルに上昇した場合も、5pips上昇したと言うことになります。

米ドルストレート（ユーロ/ドル、ポンド/ドルなど）の場合
1pip＝0.0001ドル（0.01セント）
10pip＝0.001ドル（0.1セント）
100pip＝0.01ドル（1セント）
*/
   double ret = mPips;
   if(global_Digits == 2 || global_Digits == 3){
      ret /= 100.0;
   }else if(global_Digits == 4 || global_Digits == 5){
      ret /= 10000.0;
   }
   return(ret);
}
/////////////////////////////////////////
//引数mMagicを持つ取引に対して、引数のPIPS分の利確、損切値を変更する。
// まず、comment欄の文字列を解釈して値の更新を試み、できなければ引数を用いる
//引数の利確PIPS、損切PIPSが0共に0未満の場合は、何もしない。
//既に利確、損切の値が設定されている場合(0.0より大）は更新しない。
//最終的に、全く処理をしない、または、処理を途中で続けられない場合にfalse。
/////////////////////////////////////////
bool update_AllOrdersTPSL(string mSymbol,// 通貨ペア 
                          int    mMagic, // マジックナンバー。負の時は全マジックナンバーを処理対象とする。
                          double mTP_PIPS,    // 利確PIPS
                          double mSL_PIPS     // 損切PIPS
                         ) {
   int    mOrderTicket;
   int    mBUYSELL     = 0;
   double mOpen        = 0.0;
   double mTP_Order    = 0.0;
   double mSL_Order    = 0.0;
   string mComment     = "";

   int mFlag         = true;// OrderModify実行結果。
   double tp         = 0.0; // 引数TP_PIPSを用いた利確候補値
   double sl         = 0.0; // 引数SL_PIPSを用いた損切候補値
   double mTP4Modify = 0.0; // 制限値を加味した利確候補値
   double mSL4Modify = 0.0; // 制限値を加味した損切候補値
   double mMarketinfoMODE_ASK       = 0.0;
   double mMarketinfoMODE_BID       = 0.0;
   double mMarketinfoMODE_POINT     = global_Points;
   double mMarketinfoMODE_STOPLEVEL = change_PiPS2Point(global_StopLevel);

   // 利確PIPSと損切PIPSが共に0未満の時は、何もしない。
   if(mTP_PIPS < 0.0 && mSL_PIPS < 0.0) {
      return false;
   }
   
   mMarketinfoMODE_ASK = MarketInfo(mSymbol,MODE_ASK);
   if(mMarketinfoMODE_ASK <= 0.0) {
      printf( "[%d]COMMエラー ASKの取得失敗:：%s" , __LINE__ , DoubleToStr(mMarketinfoMODE_ASK));
      return false;
   }
   mMarketinfoMODE_BID = MarketInfo(mSymbol,MODE_BID);
   if(mMarketinfoMODE_BID <= 0.0) {
      printf( "[%d]COMMエラー BIDの取得失敗:：%s" , __LINE__ , DoubleToStr(mMarketinfoMODE_BID));
      return false;
   }
   
//   double BUF_mTP_PIPS;
//   double BUF_mSL_PIPS;
   for(int i = OrdersTotal() -1; i >= 0;i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == true) {
         // 対象取引を選択する。
         if(  ( (mMagic > 0 && mMagic == OrderMagicNumber()) // 引数mMagicが正ならば一致したモノのみ。負の時は全て。
                || (mMagic < 0) )
            && ( StringLen(mSymbol) > 0 && StringCompare(mSymbol, OrderSymbol()) == 0) ) {
            mBUYSELL = OrderType();
            // 対象取引の属性値を取得する。
            mSL_Order = 0.0;
            mTP_Order = 0.0;
            if( mBUYSELL == OP_BUY || mBUYSELL == OP_SELL) {
               mComment     = OrderComment();
               
               if(avoid_update_AllOrdersTPSL(mComment) == true) {
                  // mCommentが、g_StratName01"01FRAC"を持てば、次の候補を探す
                  // mCommentが、g_StratName24"24ZZ"を持てば、次の候補を探す
                  continue;
               }

               // mCommentに<SL>111.12345</SL><TP>111.12345</TP>が含まれていれば、
               // 上書きする。
               // BUF_mTP_PIPS, BUF_mSL_PIPSにmTP_PIPSとmSL_PIPSを退避させたうえで、上書きする。
               
               double TPvalue = 0.0;
               double SLvalue = 0.0;
               get_TPSL_FromComment(mComment,  // 入力。コメント文字列 
                                    TPvalue, // 出力：<TP>～</TP>を数値化。失敗時は、-1。
                                    SLvalue  // 出力：<TP>～</TP>を数値化。失敗時は、-1。
                                    );
               mOrderTicket = OrderTicket();
               mOpen        = NormalizeDouble(OrderOpenPrice() , global_Digits);
               mSL_Order    = NormalizeDouble(OrderStopLoss()  , global_Digits);
               mTP_Order    = NormalizeDouble(OrderTakeProfit(), global_Digits);
                                                
               if(TPvalue > 0.0) {
                  tp = TPvalue;
               }
               // COMMENTに利確値、損切値が入っていない場合は、引数のmTP_PIPS又はmSL_PIPSを使って利確値、損切値を計算する。
               else {
                  // ロングの場合
                  if(mBUYSELL == OP_BUY)  {
                     tp = NormalizeDouble(mOpen  + change_PiPS2Point(mTP_PIPS), global_Digits); // 引数mTPから計算した利確の候補
                  }
      
                  // ショートの場合
                  if(mBUYSELL == OP_SELL)  {
                     tp = NormalizeDouble(mOpen  - change_PiPS2Point(mTP_PIPS), global_Digits); // 引数mTPから計算した利確の候補
                  }
               }
            
               if(SLvalue > 0.0) {
                  sl = SLvalue;
               }
               else {
                  // ロングの場合
                  if(mBUYSELL == OP_BUY)  {
                     sl  = NormalizeDouble(mOpen - change_PiPS2Point(mSL_PIPS), global_Digits); // 引数mSLから計算した損切の候補
                  }
      
                  // ショートの場合
                  if(mBUYSELL == OP_SELL)  {
                     sl = NormalizeDouble(mOpen  + change_PiPS2Point(mSL_PIPS), global_Digits); // 引数mSLから計算した損切の候補
                  }
               }
            }
/*
↓commentに利確損切のPIPSが入っている場合はこちら↓
printf( "[%d]COMM Commentを使ったTP,SL　ちけっと>%d<元の文字列>%s<　　TP=>%s<  SL=>%s<" , __LINE__ , 
OrderTicket(),
mComment,
DoubleToStr(TPvalue,global_Digits),
DoubleToStr(SLvalue,global_Digits)
);


               if(TPvalue >= 0.0) {
                  BUF_mTP_PIPS = mTP_PIPS;
                  mTP_PIPS     = TPvalue;
               }
               if(SLvalue >= 0.0) {
                  BUF_mSL_PIPS = mSL_PIPS;
                  mSL_PIPS     = SLvalue;
               }

               mOrderTicket = NormalizeDouble(OrderTicket()    , global_Digits);
               mOpen        = NormalizeDouble(OrderOpenPrice() , global_Digits);
               mSL_Order    = NormalizeDouble(OrderStopLoss()  , global_Digits);
               mTP_Order    = NormalizeDouble(OrderTakeProfit(), global_Digits);
               
printf( "[%d]COMM 設定中　ちけっと>%d<　　mTP_Order=>%s<  mSL_Order=>%s<" , __LINE__ , 
OrderTicket(),
DoubleToStr(mTP_Order,global_Digits),
DoubleToStr(mSL_Order,global_Digits)
);               
            }
            // 取引がロング、ショート以外は何もせず、次の候補を探す。
            else {
               continue;
            }

            // 取引が利確、損切共に設定されていれば何もせず、次の候補を探す。
            if(mTP_Order > 0.0 && mSL_Order > 0.0) {
printf( "[%d]COMM 取引が利確、損切共に設定されていれば何もせず、次の候補を探す" , __LINE__);        
            
               continue;
            }

            //
            // 決済値候補を計算する。
            //
            // ロングの場合
            if(mBUYSELL == OP_BUY)  {
printf( "[%d]COMM mTP_PIPS　ちけっと>%d<　　mTP_PIPS=>%s<" , __LINE__ , OrderTicket(), DoubleToStr(mTP_PIPS, global_Digits));
            
               if(mTP_PIPS >= 0.0) {
               
                  tp = NormalizeDouble(mOpen  + change_PiPS2Point(mTP_PIPS), global_Digits); // 引数mTPから計算した利確の候補
printf( "[%d]COMM 引数mTPから計算した利確の候補　ちけっと>%d<　　tp=>%s<" , __LINE__ , OrderTicket(), DoubleToStr(tp, global_Digits));
                  
               }
               else {
                  tp = 0.0;
               }
               if(mSL_PIPS >= 0.0) {
                  sl  = NormalizeDouble(mOpen - change_PiPS2Point(mSL_PIPS), global_Digits); // 引数mSLから計算した損切の候補
printf( "[%d]COMM 引数mSLから計算した利確の候補　ちけっと>%d<　　sl=>%s<" , __LINE__ , OrderTicket(), DoubleToStr(sl, global_Digits));
                  
               }
               else {
                  sl = 0.0;
               }
            }

            // ショートの場合
            if(mBUYSELL == OP_SELL)  {
               if(mTP_PIPS >= 0.0) {
                  tp = NormalizeDouble(mOpen  - change_PiPS2Point(mTP_PIPS), global_Digits); // 引数mTPから計算した利確の候補
               }
               else {
                  tp = 0.0;
               }
               if(mSL_PIPS >= 0.0) {
                  sl = NormalizeDouble(mOpen  + change_PiPS2Point(mSL_PIPS), global_Digits); // 引数mSLから計算した損切の候補
               }
               else {
                  sl = 0.0;
               }     
            }
*/

            
            
            // ロングの利益確定最小値＝これより大きな利確値のみ設定可能
            double long_tp_MIN = NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL, global_Digits);
            if(mBUYSELL == OP_BUY)  {
               if(tp > long_tp_MIN) {               
                  mTP4Modify = NormalizeDouble(tp, global_Digits);
               }
               else {
                  mTP4Modify = 0.0;
               }
            }

            // ロングの損失確定最大値＝これより小さな損切値のみ設定可能
            double long_sl_MAX = NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL, global_Digits);
            if(mBUYSELL == OP_BUY)  {
               if(sl < long_sl_MAX) {
                  mSL4Modify = NormalizeDouble(sl, global_Digits);
               }
               else {
                  mSL4Modify = 0.0;
               }
            }

            // ショートの利益確定最大値＝これより小さな利確値のみ設定可能
            double short_tp_MAX = NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL, global_Digits);
            if(mBUYSELL == OP_SELL)  {
               if(tp < short_tp_MAX) {
                  mTP4Modify = NormalizeDouble(tp, global_Digits);
               }
               else {
                  mTP4Modify = 0.0;
               }
            }

            // ショートの損失確定最小値＝これより大きな損切値のみ設定可能
            double short_sl_MIN = NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL, global_Digits);
            if(mBUYSELL == OP_SELL)  {
               if(sl > short_sl_MIN) {
                  mSL4Modify = NormalizeDouble(sl, global_Digits);
               }
               else {
                  mSL4Modify = 0.0;
               }
            }

            // 選定中の約定の設定値mSL_Order    = OrderStopLoss();  mTP_Order    = OrderTakeProfit();のうち、
            // 0より大きい値はそのまま。0以下の値を候補で更新する。
            if(mTP_Order > 0) {
               mTP4Modify = NormalizeDouble(mTP_Order, global_Digits);
            }
            else {
               // 候補mTP_Orderはそのまま
            }
            if(mSL_Order > 0) {
               mSL4Modify = NormalizeDouble(mSL_Order, global_Digits);
            }
            else {
               // 候補mSL_Orderはそのまま
            }

            // 候補mTP4Modify及びmSL4Modifyが共に0.0の時は、更新しない。
            if(mTP4Modify <= 0.0 && mSL4Modify <= 0.0) {
               // 更新しない
            }
            // 候補mTP4Modify及びmSL4Modifyが共に設定値mSL_Order,mTP_Orderの時は、更新しない。
            else if(mTP4Modify == mTP_Order && mSL4Modify == mSL_Order) {
               // 更新しない
            }
            // 上記以外は、更新する。
            else {
               int bufColor ;
               if(mBUYSELL == OP_SELL) {
                  bufColor = LINE_COLOR_SHORT;
               }
               else if(mBUYSELL == OP_BUY) {
                  bufColor = LINE_COLOR_LONG;
               }
               else {
                  bufColor = LINE_COLOR_DEFAULT;
               }
               mFlag =OrderModify(mOrderTicket, mOpen, mSL4Modify, mTP4Modify, 0, bufColor);
               if(mFlag != true) {
                  printf( "[%d]COMMエラー オーダーの修正失敗" , __LINE__);
                  printf( "[%d]COMMエラー オーダーの修正失敗:修正前 open=%s sl=%s tp=%s" , __LINE__, 
                     DoubleToStr(mOpen, global_Digits),
                     DoubleToStr(mSL_Order, global_Digits),
                     DoubleToStr(mTP_Order, global_Digits)
                  );
                  printf( "[%d]COMMエラー オーダーの修正失敗:変更値 open=%s sl=%s tp=%s" , __LINE__, 
                     DoubleToStr(mOpen, global_Digits),
                     DoubleToStr(mSL4Modify, global_Digits),
                     DoubleToStr(mTP4Modify, global_Digits)
                  );
               }
               // 上書きしたmTP_PIPS, mSL_PIPSを基に戻す
               /*
               if(TPvalue >= 0.0) {
                  mTP_PIPS = BUF_mTP_PIPS;
               }
               if(SLvalue >= 0.0) {
                  mSL_PIPS = BUF_mSL_PIPS;
               }
               */
            }    
         }
      }
   }

   return true;
}//全オーダーの指値と逆指値が設定されていることをチェックする。


/*
bool org20221220update_AllOrdersTPSL(string mSymbol,// 通貨ペア 
                          int    mMagic, // マジックナンバー。負の時は全マジックナンバーを処理対象とする。
                          double mTP_PIPS,    // 利確PIPS
                          double mSL_PIPS     // 損切PIPS
                         ) {
   int    mOrderTicket;
   int    mBUYSELL     = 0;
   double mOpen        = 0.0;
   double mTP_Order    = 0.0;
   double mSL_Order    = 0.0;
   string mComment     = "";

   int mFlag         = true;// OrderModify実行結果。
   double tp         = 0.0; // 引数TP_PIPSを用いた利確候補値
   double sl         = 0.0; // 引数SL_PIPSを用いた損切候補値
   double mTP4Modify = 0.0; // 制限値を加味した利確候補値
   double mSL4Modify = 0.0; // 制限値を加味した損切候補値
   double mMarketinfoMODE_ASK       = 0.0;
   double mMarketinfoMODE_BID       = 0.0;
   double mMarketinfoMODE_POINT     = global_Points;
   double mMarketinfoMODE_STOPLEVEL = change_PiPS2Pointglobal_StopLevel);

   // 利確PIPSと損切PIPSが共に0未満の時は、何もしない。
   if(mTP_PIPS < 0.0 && mSL_PIPS < 0.0) {
      return false;
   }
   
   mMarketinfoMODE_ASK = MarketInfo(mSymbol,MODE_ASK);
   if(mMarketinfoMODE_ASK <= 0.0) {
      printf( "[%d]COMMエラー ASKの取得失敗:：%s" , __LINE__ , DoubleToStr(mMarketinfoMODE_ASK));
      return false;
   }
   mMarketinfoMODE_BID = MarketInfo(mSymbol,MODE_BID);
   if(mMarketinfoMODE_BID <= 0.0) {
      printf( "[%d]COMMエラー BIDの取得失敗:：%s" , __LINE__ , DoubleToStr(mMarketinfoMODE_BID));
      return false;
   }
   
   for(int i = OrdersTotal() -1; i >= 0;i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == true) {
         // 対象取引を選択する。
         if(  ( (mMagic > 0 && mMagic == OrderMagicNumber()) // mMagicが正ならば一致したモノのみ。負の時は全て。
                || (mMagic < 0) )
            && StringCompare(mSymbol, OrderSymbol()) == 0 ) {
            mBUYSELL = OrderType();
            // 対象取引の属性値を取得する。
            if( mBUYSELL == OP_BUY || mBUYSELL == OP_SELL) {
               mComment     = OrderComment();
//mCommentに<SL>111.12345</SL><TP>111.12345</TP>が含まれていれば、
//上書きする。
               if(avoid_update_AllOrdersTPSL(mComment) == true) {
                  // mCommentが、g_StratName01"01FRAC"を持てば、次の候補を探す
                  // mCommentが、g_StratName24"24ZZ"を持てば、次の候補を探す

//BUF_TP_PIPS, BUF_SL_PIPSをmTP_PIPSとmSL_PIPSに戻す。

                  continue;
               }
               mOrderTicket = NormalizeDouble(OrderTicket()    , global_Digits);
               mOpen        = NormalizeDouble(OrderOpenPrice() , global_Digits);
               mSL_Order    = NormalizeDouble(OrderStopLoss()  , global_Digits);
               mTP_Order    = NormalizeDouble(OrderTakeProfit(), global_Digits);
               
            }
            // 取引がロング、ショート以外は何もせず、次の候補を探す。
            else {
               continue;
            }

            // 取引が利確、損切共に設定されていれば何もせず、次の候補を探す。。
            if(mTP_Order > 0.0 && mSL_Order > 0.0) {
               continue;
            }

            //
            // 決済値候補を計算する。
            //
            // ロングの場合
            if(mBUYSELL == OP_BUY)  {
               if(mTP_PIPS >= 0.0) {
                  tp = NormalizeDouble(mOpen  + mTP_PIPS * mMarketinfoMODE_POINT, global_Digits); // 引数mTPから計算した利確の候補
               }
               else {
                  tp = 0.0;
               }
               if(mSL_PIPS >= 0.0) {
                  sl  = NormalizeDouble(mOpen - mSL_PIPS * mMarketinfoMODE_POINT, global_Digits); // 引数mSLから計算した損切の候補
               }
               else {
                  sl = 0.0;
               }
            }

            // ショートの場合
            if(mBUYSELL == OP_SELL)  {
               if(mTP_PIPS >= 0.0) {
                  tp = NormalizeDouble(mOpen  - mTP_PIPS * mMarketinfoMODE_POINT, global_Digits); // 引数mTPから計算した利確の候補
               }
               else {
                  tp = 0.0;
               }
               if(mSL_PIPS >= 0.0) {
                  sl = NormalizeDouble(mOpen  + mSL_PIPS * mMarketinfoMODE_POINT, global_Digits); // 引数mSLから計算した損切の候補
               }
               else {
                  sl = 0.0;
               }     
            }

            // ロングの利益確定最小値＝これより大きな利確値のみ設定可能
            double long_tp_MIN = NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL, global_Digits);
            if(mBUYSELL == OP_BUY)  {
               if(tp > long_tp_MIN) {
                  mTP4Modify = NormalizeDouble(tp, global_Digits);
               }
               else {
                  mTP4Modify = 0.0;
               }
            }

            // ロングの損失確定最大値＝これより小さな損切値のみ設定可能
            double long_sl_MAX = NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL, global_Digits);
            if(mBUYSELL == OP_BUY)  {
               if(sl < long_sl_MAX) {
                  mSL4Modify = NormalizeDouble(sl, global_Digits);
               }
               else {
                  mSL4Modify = 0.0;
               }
            }

            // ショートの利益確定最大値＝これより小さな利確値のみ設定可能
            double short_tp_MAX = NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL, global_Digits);
            if(mBUYSELL == OP_SELL)  {
               if(tp < short_tp_MAX) {
                  mTP4Modify = NormalizeDouble(tp, global_Digits);
               }
               else {
                  mTP4Modify = 0.0;
               }
            }

            // ショートの損失確定最小値＝これより大きな損切値のみ設定可能
            double short_sl_MIN = NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL, global_Digits);
            if(mBUYSELL == OP_SELL)  {
               if(sl > short_sl_MIN) {
                  mSL4Modify = NormalizeDouble(sl, global_Digits);
               }
               else {
                  mSL4Modify = 0.0;
               }
            }

            // 選定中の約定の設定値mSL_Order    = OrderStopLoss();  mTP_Order    = OrderTakeProfit();のうち、
            // 0より大きい値はそのまま。0以下の値を候補で更新する。
            if(mTP_Order > 0) {
               mTP4Modify = NormalizeDouble(mTP_Order, global_Digits);
            }
            else {
               // 候補mTP_Orderはそのまま
            }
            if(mSL_Order > 0) {
               mSL4Modify = NormalizeDouble(mSL_Order, global_Digits);
            }
            else {
               // 候補mSL_Orderはそのまま
            }

            // 候補mTP4Modify及びmSL4Modifyが共に0.0の時は、更新しない。
            if(mTP4Modify <= 0.0 && mSL4Modify <= 0.0) {
               // 更新しない
            }
            // 候補mTP4Modify及びmSL4Modifyが共に設定値mSL_Order,mTP_Orderの時は、更新しない。
            else if(mTP4Modify == mTP_Order && mSL4Modify == mSL_Order) {
               // 更新しない
            }
            // 上記以外は、更新する。
            else {
               int bufColor ;
               if(mBUYSELL == OP_SELL) {
                  bufColor = LINE_COLOR_SHORT;
               }
               else if(mBUYSELL == OP_BUY) {
                  bufColor = LINE_COLOR_LONG;
               }
               else {
                  bufColor = LINE_COLOR_DEFAULT;
               }
               mFlag =OrderModify(mOrderTicket, mOpen, mSL4Modify, mTP4Modify, 0, bufColor);
               if(mFlag != true) {
                  printf( "[%d]COMMエラー オーダーの修正失敗" , __LINE__);
                  printf( "[%d]COMMエラー オーダーの修正失敗:修正前 open=%s sl=%s tp=%s" , __LINE__, 
                     DoubleToStr(mOpen, global_Digits),
                     DoubleToStr(mSL_Order, global_Digits),
                     DoubleToStr(mTP_Order, global_Digits)
                  );
                  printf( "[%d]COMMエラー オーダーの修正失敗:変更値 open=%s sl=%s tp=%s" , __LINE__, 
                     DoubleToStr(mOpen, global_Digits),
                     DoubleToStr(mSL4Modify, global_Digits),
                     DoubleToStr(mTP4Modify, global_Digits)
                  );
               }
            }
         }
      }
   }

   return true;
}//全オーダーの指値と逆指値が設定されていることをチェックする。

*/

/*
bool orgupdate_AllOrdersTPSL(string mSymbol, int mMagic, double mTP, double mSL) {
   int    mOrderTicket = 0;
   int    mBUYSELL     = 0;
   double minSL        = 0.0;
   double mOpen        = 0.0;
   double mTP_Order    = 0.0;
   double mSL_Order    = 0.0;
   string mComment     = "";

   int mFlag       = true;  // OrderModify実行結果。
   double mTP_BUY  = 0.0;
   double mSL_BUY  = 0.0;
   double mTP_SELL = 0.0;
   double mSL_SELL = 0.0;

   double mMarketinfoMODE_ASK       = 0.0;
   double mMarketinfoMODE_BID       = 0.0;
   double mMarketinfoMODE_POINT     = global_Points;
   double mMarketinfoMODE_STOPLEVEL = global_StopLevel;

   // 引数チェック
   if(mMagic < 0) {
      return false;
   }

   if(mTP < 0.0 && mSL < 0.0) {
      return false;
   }
   
   mMarketinfoMODE_ASK = MarketInfo(mSymbol,MODE_ASK);
   if(mMarketinfoMODE_ASK <= 0.0) {
      printf( "[%d]COMMエラー ASKの取得失敗:：%s" , __LINE__ , DoubleToStr(mMarketinfoMODE_ASK));
      return false;
   }
   mMarketinfoMODE_BID = MarketInfo(mSymbol,MODE_BID);
   if(mMarketinfoMODE_BID <= 0.0) {
      printf( "[%d]COMMエラー BIDの取得失敗:：%s" , __LINE__ , DoubleToStr(mMarketinfoMODE_BID));
      return false;
   }
   
   for(int i = OrdersTotal() -1; i >= 0;i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == true) {

         // 対象取引を選択する。
         if(mMagic == OrderMagicNumber()
            && StringCompare(mSymbol, OrderSymbol()) == 0 ) {
            mBUYSELL = OrderType();
            // 対象取引の属性値を取得する。
            if( mBUYSELL == OP_BUY || mBUYSELL == OP_SELL) {
               mComment     = OrderComment();
               if(avoid_update_AllOrdersTPSL(mComment) == true) {
                  // mCommentが、g_StratName01"01FRAC"を持てば、次の候補を探す
                  // mCommentが、g_StratName24"24ZZ"を持てば、次の候補を探す

                  continue;
               }
               mOrderTicket = OrderTicket();
               mOpen        = OrderOpenPrice();
               mSL_Order    = OrderStopLoss();
               mTP_Order    = OrderTakeProfit();
               
            }
            // 取引がロング、ショート以外は何もせず、次の候補を探す。
            else {
               continue;
            }

            //
            // 決済値候補を計算する。
            //
            // ロングの場合
            if(mTP >= 0.0) {
               mTP_BUY = NormalizeDouble(mOpen  + mTP * mMarketinfoMODE_POINT, global_Digits); // 引数mTPから計算した利確の候補
            }
            else {
               mTP_BUY = 0.0;
            }
            if(mSL >= 0.0) {
               mSL_BUY  = NormalizeDouble(mOpen  - mSL * mMarketinfoMODE_POINT, global_Digits); // 引数mSLから計算した損切の候補
            }
            else {
               mSL_BUY = 0.0;
            }
            
            // ショートの場合
            if(mTP >= 0.0) {
               mTP_SELL = NormalizeDouble(mOpen  - mTP * mMarketinfoMODE_POINT, global_Digits); // 引数mTPから計算した利確の候補
            }
            else {
               mTP_SELL = 0.0;
            }
            if(mSL >= 0.0) {
               mSL_SELL = NormalizeDouble(mOpen  + (double)mSL * mMarketinfoMODE_POINT, global_Digits); // 引数mSLから計算した損切の候補
            }
            else {
               mSL_SELL = 0.0;
            }     
    
            //
            // 利確、損切値を更新する。
            //
            // ロングの場合 
            //
            if(mBUYSELL == OP_BUY) {      
               // オーダーに利確、損切が両方設定されていない場合。両方または可能な一方を変更する。
               if( (mSL_Order <= 0.0) && (mTP_Order <= 0.0) ) { // オーダーにtp, slが設定されていない
                 
                  // ロングの利確、損切候補値。
                  // ロングの利益確定は、その時のASK＋ストップレベルより大きくなくてはならない。
                  // ロングの損切は、その時のBID-ストップレベルより小さくなくてはならない。
                  // 参考資料：https://toushi-strategy.com/mt4/stoplevel/
                  // 急な値動きにより、tpがASK＋ストップレベル以下、もしくはslがBID-ストップレベル以上の時は、変更見送り。


   
                  // 利確、損切の両方を変更しようとして、利確、損切の両方が変更可能な値段の場合
                  if(mTP_BUY > 0 && NormalizeDouble(mTP_BUY, global_Digits)  > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits)  + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT &&
                     mSL_BUY > 0 && NormalizeDouble(mSL_BUY, global_Digits)  < NormalizeDouble(mMarketinfoMODE_BID, global_Digits)  - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
//printf( "[%d]COMM BUY　利確、損切が両方設定されていない場合。両方変更可能" , __LINE__);
                     
                     mFlag = OrderModify(mOrderTicket, mOpen, mSL_BUY, mTP_BUY, 0, LINE_COLOR_LONG);
                     if(mFlag != true) {
                        printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                     }
                  }

                  // 利確、損切の両方を変更しようとして、利確のみが変更可能な場合
                  else if( (NormalizeDouble(mTP_BUY, global_Digits) > 0.0 && NormalizeDouble(mTP_BUY, global_Digits)  >  NormalizeDouble(mMarketinfoMODE_ASK, global_Digits)  + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) &&
                           ( (mSL_BUY <= 0.0)
                              || (NormalizeDouble(mSL_BUY, global_Digits) > 0.0 && NormalizeDouble(mSL_BUY, global_Digits) >= NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) ) ){
                     mFlag =OrderModify(mOrderTicket, mOpen, mSL_Order, mTP_BUY, 0, LINE_COLOR_LONG);
                     if(mFlag != true) {
                        printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                     }
                  }
                  // 利確、損切の両方を変更しようとして、損切のみが変更可能な場合

                  // 利確、損切の両方を変更しようとして、損切のみが変更可能な場合
                  else if( ( (NormalizeDouble(mTP_BUY, global_Digits) <= 0.0) 
                              || (NormalizeDouble(mTP_BUY, global_Digits) > 0 && NormalizeDouble(mTP_BUY, global_Digits) <= NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT))
                               &&
                           (NormalizeDouble(mSL_BUY, global_Digits) > 0 && NormalizeDouble(mSL_BUY, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) ){
                     mFlag =OrderModify(mOrderTicket, mOpen, mSL_BUY, mTP_Order, 0, LINE_COLOR_LONG);
                     if(mFlag != true) {
                        printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                     }
                  }                  
               }
               // オーダーに利確のみが設定されていない場合。＝利確値を変更する
               else if((NormalizeDouble(mSL_Order, global_Digits) > 0.0) && (NormalizeDouble(mTP_Order, global_Digits) <= 0.0)) { // オーダーにtpが設定されていない
                  if(NormalizeDouble(mTP_BUY, global_Digits) > 0.0 && NormalizeDouble(mTP_BUY, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
                     mFlag =OrderModify(mOrderTicket, mOpen, mSL_Order, mTP_BUY, 0, LINE_COLOR_LONG);
                     if(mFlag != true) {
                        printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                     }                  
                  }
                  else {
                  }
               }
                // オーダーに損切のみが設定されていない場合。
               else if(NormalizeDouble(mSL_Order, global_Digits) <= 0.0 && NormalizeDouble(mTP_Order, global_Digits) > 0.0) { // オーダーにslが設定されていない
                  if(NormalizeDouble(mSL_BUY, global_Digits) > 0.0 &&  NormalizeDouble(mSL_BUY, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
                     mFlag =OrderModify(mOrderTicket, mOpen, mSL_BUY, mTP_Order, 0, LINE_COLOR_LONG);
                     if(mFlag != true) {
                        printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                     }                  
                  }
                  else {   
                  }
                  
               }

               //  利確と損切が設定済みの場合。何もしない。  
               else {
               }
            }
               
            // ショートの場合 
            //
            else if(mBUYSELL == OP_SELL) {
               // オーダーに利確、損切が両方設定されていなかった場合。両方または一方を変更する。
               if(mSL_Order <= 0.0  && mTP_Order <= 0.0) {
                  // ショートの利益確定は、その時のBID-ストップレベルより小さくなくてはならない。
                  // ショートの損切は、その時のASK+ストップレベルより大きくなくてはならない。
                  // 参考資料：https://toushi-strategy.com/mt4/stoplevel/　　から、推測。
                  // 急な値動きにより、tpがBID-ストップレベル以上、もしくはslがASK+ストップレベル以下の時は、変更見送り。
//printf( "[%d]COMM 損切候補：%s →　%s以上の時にのみ変更可能" , __LINE__, DoubleToStr(mSL_SELL), DoubleToStr(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
//printf( "[%d]COMM 利確候補：%s →　%s未満の時にのみ変更可能" , __LINE__, DoubleToStr(mTP_SELL), DoubleToStr(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT));
                  // 利確、損切の両方を変更しようとして、利確、損切の両方が変更可能な場合                  
                  if(NormalizeDouble(mTP_SELL, global_Digits) > 0.0 && NormalizeDouble(mTP_SELL, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT &&
                     NormalizeDouble(mSL_SELL, global_Digits) > 0.0 && NormalizeDouble(mSL_SELL, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
                     mFlag =OrderModify(mOrderTicket, mOpen, mSL_SELL, mTP_SELL, 0, LINE_COLOR_SHORT);
                     if(mFlag != true) {
                        printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                     }
                  }

                  // 利確、損切の両方を変更しようとして、利確のみが変更可能な場合
                  else if((NormalizeDouble(mTP_SELL, global_Digits) > 0.0 && NormalizeDouble(mTP_SELL, global_Digits) <  NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) &&
                          ((NormalizeDouble(mSL_SELL, global_Digits) <= 0.0) 
                            || (NormalizeDouble(mSL_SELL, global_Digits) > 0.0 && NormalizeDouble(mSL_SELL, global_Digits) <= NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) ) ) {
                     mFlag =OrderModify(mOrderTicket, mOpen, mSL_Order, mTP_SELL, 0, LINE_COLOR_SHORT);
                     if(mFlag != true) {
                           printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                     }
                  }

                  // 利確、損切の両方を変更しようとして、損切のみが変更可能な場合
                  if( ((NormalizeDouble(mTP_SELL, global_Digits) <= 0.0)
                        || (NormalizeDouble(mTP_SELL, global_Digits) > 0 && NormalizeDouble(mTP_SELL, global_Digits) >= NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) ) &&
                      (NormalizeDouble(mSL_SELL, global_Digits) > 0.0 && NormalizeDouble(mSL_SELL, global_Digits) >  NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) ){
                     mFlag =OrderModify(mOrderTicket, mOpen, mSL_SELL, mTP_Order, 0, LINE_COLOR_SHORT);
                     if(mFlag != true) {
                        printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                     }
                  }                                          
               } // 利確と損切両方が設定されていない場合の処理は、ここまで。
               


 

                // オーダーに利確のみが設定されていない場合。＝利確値を変更する
               else if(NormalizeDouble(mSL_Order, global_Digits) > 0.0 && NormalizeDouble(mTP_Order, global_Digits) <= 0.0) { // オーダーにtpが設定されていない                                  
                 if(NormalizeDouble(mTP_SELL, global_Digits) > 0.0 && NormalizeDouble(mTP_SELL, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
                     mFlag =OrderModify(mOrderTicket, mOpen, mSL_Order, mTP_SELL, 0, LINE_COLOR_SHORT);
                     if(mFlag != true) {
                        printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                     }                      
                  }
               }

               // オーダーに損切のみが設定されていない場合。
               else if(NormalizeDouble(mSL_Order, global_Digits) <= 0.0 && NormalizeDouble(mTP_Order, global_Digits) > 0.0) { // オーダーにslが設定されていない
                  if(NormalizeDouble(mSL_SELL, global_Digits) > 0.0 && NormalizeDouble(mSL_SELL, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
                     mFlag =OrderModify(mOrderTicket, mOpen, mSL_SELL, mTP_Order, 0, LINE_COLOR_SHORT);
                     if(mFlag != true) {
                        printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                     }
                  }
               }

               //  利確と損切が設定済みの場合。何もしない。  
               else {
               }                 
            }

            // ロングでもショートでもない場合 
            //
            else {
                  // ここはロングでもショートでもない場合。何もしない。
            }
         } // Magicnumberが、引数と一致した場合の末尾
      }    // if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == true) の末尾
   }       // for(int i = OrdersTotal() -1; i >= 0;i--) {の末尾


   // 01FRACや24ZZのように、専用のTP, SL設定用関数を動かす必要のあるオーダーがあれば、
   // 個別のプログラムで実行する。
   // 

   return true;
}//全オーダーの指値と逆指値が設定されていることをチェックする。

*/
/*
bool old_update_AllOrdersTPSL2(string mSymbol, int mMagic, double mTP, double mSL) {
   int mOrderTicket = 0;
   int mBUYSELL   = 0;
   double minSL   = 0.0;
   double mOpen   = 0.0;
   double mTP_Order  = 0.0;
   double mSL_Order  = 0.0;
   int mFlag      = true;  // OrderModify実行結果。
   double mTP_BUY = 0.0;
   double mSL_BUY = 0.0;
   double mTP_SELL = 0.0;
   double mSL_SELL = 0.0;

   double mMarketinfoMODE_ASK = 0.0;
   double mMarketinfoMODE_BID = 0.0;
   double mMarketinfoMODE_POINT = global_Points;
   double mMarketinfoMODE_STOPLEVEL = global_StopLevel;

   // 引数チェック
   if(mMagic < 0) return false;
   if(mTP < 0.0 && mSL < 0.0) return false;
   
   mMarketinfoMODE_ASK = MarketInfo(mSymbol,MODE_ASK);
   if(mMarketinfoMODE_ASK <= 0.0) {
      printf( "[%d]COMMエラー ASKの取得失敗:：%s" , __LINE__ , DoubleToStr(mMarketinfoMODE_ASK));
      return false;
   }
   mMarketinfoMODE_BID = MarketInfo(mSymbol,MODE_BID);
   if(mMarketinfoMODE_BID <= 0.0) {
      printf( "[%d]COMMエラー BIDの取得失敗:：%s" , __LINE__ , DoubleToStr(mMarketinfoMODE_BID));
      return false;
   }
   
   for(int i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == true) {

         // 対象取引を選択する。
         if(mMagic == OrderMagicNumber()
            && StringCompare(mSymbol, OrderSymbol()) == 0 ) {
            mBUYSELL = OrderType();
            // 対象取引の属性値を取得する。
            if( mBUYSELL == OP_BUY || mBUYSELL == OP_SELL) {
               mOrderTicket = OrderTicket();
               mOpen        = OrderOpenPrice();
               mSL_Order    = OrderStopLoss();
               mTP_Order    = OrderTakeProfit();
            }
            // 取引がロング、ショート以外は何もせず、次の候補を探す。
            else {
               continue;
            }

            //
            // 決済値候補を計算する。
            //
            // ロングの場合
            if(mTP >= 0) {
               mTP_BUY = NormalizeDouble(mOpen, global_Digits)  + (double)mTP * mMarketinfoMODE_POINT; // 引数mTPから計算した利確の候補
            }
            else {
               mTP_BUY = 0.0;
            }
            if(mSL >= 0) {
               mSL_BUY  = NormalizeDouble(mOpen, global_Digits)  - (double)mSL * mMarketinfoMODE_POINT; // 引数mSLから計算した損切の候補
            }
            else {
               mSL_BUY = 0.0;
            }
            
            // ショートの場合
            if(mTP >= 0) {
               mTP_SELL = NormalizeDouble(mOpen, global_Digits)  - (double)mTP * mMarketinfoMODE_POINT; // 引数mTPから計算した利確の候補
            }
            else {
               mTP_SELL = 0.0;
            }
            if(mSL >= 0) {
               mSL_SELL = NormalizeDouble(mOpen, global_Digits)  + (double)mSL * mMarketinfoMODE_POINT; // 引数mSLから計算した損切の候補
            }
            else {
               mSL_SELL = 0.0;
            }     

       
            //
            // 利確、損切値を更新する。
            //
            // ロングの場合 
            //
            if(mBUYSELL == OP_BUY) {      
               // ロングの利確、損切候補値。
               // ロングの利益確定は、その時のASK＋ストップレベルより大きくなくてはならない。
               // ロングの損切は、その時のBID-ストップレベルより小さくなくてはならない。
               // 参考資料：https://toushi-strategy.com/mt4/stoplevel/
               // 急な値動きにより、tpがASK＋ストップレベル以下、もしくはslがBID-ストップレベル以上の時は、変更見送り。

               // ロングの利確値を計算する
               if(mTP_BUY > 0.0 && NormalizeDouble(mTP_BUY, global_Digits)  > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits)  + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
                  // 候補値mTP_BUYとオーダー設定値の有利な方を採用する。
                  if(NormalizeDouble(mTP_BUY, global_Digits) > NormalizeDouble(mTP_Order, global_Digits) ) {
                     // 候補値をそのまま使う
                  }
                  else {
                  // 候補値mTP_BUYをオーダー設定値で上書きする。
                     mTP_BUY = mTP_Order;
                  }
               }
               else {
                  // 候補値mTP_BUYをオーダー設定値で上書きする。
                  mTP_BUY = mTP_Order;
               }

               // ロングの損切値を計算する
               if(mSL_BUY > 0.0 && NormalizeDouble(mSL_BUY, global_Digits)  < NormalizeDouble(mMarketinfoMODE_BID, global_Digits)  - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
                  // 候補値mSL_BUYとオーダー設定値の有利な方を採用する。
                  if(NormalizeDouble(mSL_BUY, global_Digits) > NormalizeDouble(mSL_Order, global_Digits) ) {
                     // 候補値をそのまま使う
                  }
                  else {
                  // 候補値mSL_BUYをオーダー設定値で上書きする。
                     mSL_BUY = mSL_Order;
                  }
               }
               else {
                  // 候補値mSL_BUYをオーダー設定値で上書きする。
                  mSL_BUY = mSL_Order;
               }

               // 候補値mTP_BUY, mSL_BUYのどちらかがもしくはry方がオーダー設定値と異なる場合だけ、OrderModifyを実行する。
               if( NormalizeDouble(mTP_BUY, global_Digits) != NormalizeDouble(mTP_Order, global_Digits)
                  ||
                   NormalizeDouble(mSL_BUY, global_Digits) != NormalizeDouble(mSL_Order, global_Digits) ) { 
                  mFlag =OrderModify(mOrderTicket, mOpen, mSL_BUY, mTP_BUY, 0, LINE_COLOR_LONG);
                  if(mFlag != true) {
                     printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                  }
               }
            }  // ロングの場合は、ここまで。 

               
            // ショートの場合 
            //
            else if(mBUYSELL == OP_SELL) {
               // ショートの利益確定は、その時のBID-ストップレベルより小さくなくてはならない。
               // ショートの損切は、その時のASK+ストップレベルより大きくなくてはならない。
               // 参考資料：https://toushi-strategy.com/mt4/stoplevel/　　から、推測。
               // 急な値動きにより、tpがBID-ストップレベル以上、もしくはslがASK+ストップレベル以下の時は、変更見送り。


               // ショートの利確値を計算する
               if(mTP_SELL > 0.0 && NormalizeDouble(mTP_SELL, global_Digits)  < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
                  // 候補値mTP_SELLとオーダー設定値の有利な方を採用する。
                  if(NormalizeDouble(mTP_SELL, global_Digits) < NormalizeDouble(mTP_Order, global_Digits) ) {
                     // 候補値をそのまま使う
                  }
                  else {
                  // 候補値mTP_BUYをオーダー設定値で上書きする。
                     mTP_SELL = mTP_Order;
                  }
               }
               else {
                  // 候補値mTP_SELLをオーダー設定値で上書きする。
                  mTP_SELL = mTP_Order;
               }

               // ショートの損切値を計算する
               if(mSL_SELL > 0.0 && NormalizeDouble(mSL_SELL, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
                  // 候補値mSL_SELLとオーダー設定値の有利な方を採用する。
                  if(NormalizeDouble(mSL_SELL, global_Digits) < NormalizeDouble(mSL_Order, global_Digits) ) {
                     // 候補値をそのまま使う
                  }
                  else {
                  // 候補値mSL_SELLをオーダー設定値で上書きする。
                     mSL_SELL = mSL_Order;
                  }
               }
               else {
                  // 候補値mSL_SELLをオーダー設定値で上書きする。
                  mSL_SELL = mSL_Order;
               }

               // 候補値mTP_SELL, mSL_SELLのどちらかがもしくはry方がオーダー設定値と異なる場合だけ、OrderModifyを実行する。
               if( NormalizeDouble(mTP_SELL, global_Digits) != NormalizeDouble(mTP_Order, global_Digits)
                  ||
                   NormalizeDouble(mSL_SELL, global_Digits) != NormalizeDouble(mSL_Order, global_Digits) ) { 
                  mFlag =OrderModify(mOrderTicket, mOpen, mSL_SELL, mTP_SELL, 0, LINE_COLOR_SHORT);
                  if(mFlag != true) {
                     printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
                  }
               }








            } // ショートの場合は、ここまで。 
            // ロングでもショートでもない場合 
            //
            else {
                  // ここはロングでもショートでもない場合。何もしない。
            }
         } // Magicnumberが、引数と一致した場合の末尾
      } // if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == true) の末尾
   }
   return true;
}//全オーダーの指値と逆指値が設定されていることをチェックする。
*/
///////////////////////////////////////////////////////
// 損切値が設定されている場合で、指定したpips数だけ利益が出る指値（＝候補値）に変更できれば変更する。
// 引数mPipsは、0以上とする。
// 例えば、
//   ロングの場合は、　候補値が、設定済み損切値より大きい場合のみ変更。
//   ショートの場合は、候補値が、設定済み損切値より小さい場合のみ変更。
///////////////////////////////////////////////////////
bool flooringSL(string mSymbol,
                int    mMagic,   // flooring設定をする約定のマジックナンバー
                double mPips,    // flooringで切り上げるPIPS数
                bool   mContinue // trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。
                ) {
   int    mOrderTicket = 0;
   double mSL     = 0.0;	
   double mTP     = 0.0;	
   int    mBUYSELL = 0;	
   double minSL   = 0.0;	
   double mOpen   = 0.0;	
   double mClose  = 0.0;	
   int mFlag      = 0;	
   bool ret = true;

   // mMagicが負は想定していない。
   if(mMagic < 0) {
      return true;  // 何もせず、正常終了とする。
   }
   
   // mPipsが負は想定していない。
   if(mPips < 0) {
      return true;  // 何もせず、正常終了とする。
   }   

   double mMarketinfoMODE_ASK = 0.0;
   double mMarketinfoMODE_BID = 0.0;
   double mMarketinfoMODE_POINT = 0.0;
   double mMarketinfoMODE_STOPLEVEL = 0.0;

   mMarketinfoMODE_ASK       = MarketInfo(mSymbol,MODE_ASK);
   mMarketinfoMODE_BID       = MarketInfo(mSymbol,MODE_BID);
   mMarketinfoMODE_POINT     = global_Points; // MarketInfo(mSymbol,MODE_POINT);
   mMarketinfoMODE_STOPLEVEL = change_PiPS2Point(global_StopLevel); //MarketInfo(mSymbol,MODE_STOPLEVEL);      

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
         double tp = 0.0;
         double sl = 0.0;
         double bufSL = 0.0;
         double minimalSL = 0.0;
         double maxmalSL = 0.0;
	 
         // マジックナンバーが同じ取引が、ロングの場合
         if(mBUYSELL == OP_BUY) {
            // mContinueが、trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。
            if(mContinue == true) {
               // 損切値が、損失を発生させる値の時は、約定値からmPipsだけ有利な額に更新する。ただし、より、有利になる場合に限る
               if(NormalizeDouble(mSL, global_Digits) < NormalizeDouble(mOpen, global_Digits)) {
                  bufSL = NormalizeDouble(mOpen, global_Digits) + NormalizeDouble(change_PiPS2Point(mPips), global_Digits); // 引数を使ったロングの損切候補
               }
               // 損切値が、損失を発生させるものではないときは、設定値からmPipsずつ切り上げる
               else {
                  bufSL = NormalizeDouble(mSL,   global_Digits) + NormalizeDouble(change_PiPS2Point(mPips), global_Digits); // 引数を使ったロングの損切候補
               }
            }
            else if(mContinue == false) {
               // 損切値が、損失を発生させる値の時は、約定値からmPipsだけ有利な額に更新する。
               if(NormalizeDouble(mSL, global_Digits) < NormalizeDouble(mOpen, global_Digits)) {
                  bufSL = NormalizeDouble(mOpen, global_Digits) + NormalizeDouble(change_PiPS2Point(mPips), global_Digits); // 引数を使ったロングの損切候補
               }
               // 損切値が、損失を発生させるものではないときは、何もしない
               else {
                  // 何もしない
               }
            }
            // ロングの損切は、その時のBID-ストップレベルより小さくなくてはならない。
            // 参考資料：https://toushi-strategy.com/mt4/stoplevel/
            maxmalSL = NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL, global_Digits);

            // 損切候補bufSLが、取りうる最大値maxmalSLより小さく、
            // 設定済み損切値より大きければ、
            // 値を変更する。
            if(NormalizeDouble(bufSL, global_Digits) < NormalizeDouble(maxmalSL, global_Digits) 
               && NormalizeDouble(bufSL, global_Digits) > NormalizeDouble(mSL, global_Digits)) {
               mOrderTicket = OrderTicket();
               mTP = OrderTakeProfit();
               mFlag =OrderModify(mOrderTicket, mOpen, bufSL, mTP, 0, LINE_COLOR_LONG);
               if(mFlag != true) {
                  ret = false;
                  printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
               }  
            }
			
         }

         // マジックナンバーが同じ取引が、ショートの場合
         else if(mBUYSELL == OP_SELL) {		
            if(mContinue == true) {
               // 損切値が、損失を発生させる値の時は、約定値からmPipsだけ有利な額に更新する。
               if(NormalizeDouble(mSL, global_Digits) > NormalizeDouble(mOpen, global_Digits)) {
                  bufSL = NormalizeDouble(mOpen, global_Digits) - NormalizeDouble(change_PiPS2Point(mPips), global_Digits); // 引数を使ったショートの損切候補
               }
               // 損切値が、損失を発生させるものではないときは、mPipsずつ切り下げる
               else {
                  bufSL = NormalizeDouble(mSL  , global_Digits) - NormalizeDouble(change_PiPS2Point(mPips), global_Digits); // 引数を使ったショートの損切候補
               }
            }
            else if(mContinue == false) {
               // 損切値が、損失を発生させる値の時は、約定値からmPipsだけ有利な額に更新する。
               if(NormalizeDouble(mSL, global_Digits) > NormalizeDouble(mOpen, global_Digits)) {
                  bufSL = NormalizeDouble(mOpen, global_Digits) - NormalizeDouble(change_PiPS2Point(mPips), global_Digits); // 引数を使ったショートの損切候補
               }
               // 損切値が、損失を発生させるものではないときは、何もしない
               else {
                  // 何もしない
               }
            }            
            // ショートの損切は、その時のASK+ストップレベルより大きくなくてはならない。
            // 参考資料：https://toushi-strategy.com/mt4/stoplevel/　　から、推測。
            minimalSL = NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL, global_Digits);
          
            // 損切候補bufSLが、取りうる最小値minimalSLより大きく、
            // 設定済み損切値より小さければ、
            // 値を変更する。            
            if(NormalizeDouble(bufSL, global_Digits) > NormalizeDouble(minimalSL, global_Digits)
               && NormalizeDouble(bufSL, global_Digits) < NormalizeDouble(mSL,global_Digits) ) {
               mOrderTicket = OrderTicket();
               mTP = OrderTakeProfit();
               mFlag =OrderModify(mOrderTicket,mOpen, bufSL, mTP, 0, LINE_COLOR_SHORT);	
               if(mFlag != true) {
                  ret = false;
                  printf( "[%d]COMMエラー オーダーの修正失敗：%s" , __LINE__, GetLastError());
               }  	               	
            }
		
         }	
         else {	
         }
      }	
   }	
   return ret;	
}//損切値を切り上げる。	






  
  
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

//+------------------------------------------------------------------+
//|   実取引の送信
//|   ※ 残高不足の場合は、発注しない
//|   ※ スプレッドが広がりすぎている時は、発注しない
//|   ※ 引数のdouble stoploss, double takeprofitが、発注制限値を満たしていなければ、発注しない
//|     →　トレーディングラインを使った発注可否は、この関数内では判断しない。
//|   ※ 引数で渡された利確値、損切値が、０より大きい場合に限り、OrderSendのコメント欄に、<TP>・・・</TP><SL>・・・</SL>を追加する。
//|   ※ 引数で渡された利確値、損切値が、ストップレベルの制限に違反する場合は、違反した値を設定しない(＝0.0とする。）
//|   入力：OrderSend関数に必要な引数
//|   出力：チケットナンバー                                       |
//+------------------------------------------------------------------+
int mOrderSend5(string symbol, int cmd, double volume, double price, int slippage, double stoploss, double takeprofit, string comment=NULL, int magic=0, datetime expiration=0, color arrow_color=CLR_NONE) {
   bool mFlag = false;
   int Index = 0;
   int ticket_num =-1;
   double ATR_1 = 0.0;
   double mOpenPrice = 0.0;  // 設定中の約定値
   double mTP = 0.0;         // 設定中の利確値
   double mSL = 0.0;         // 設定中の損切値
   double mTP4Modify = 0.0;  // 変更先の利確値
   double mSL4Modify = 0.0;  // 変更先の損切値

   double mMarketinfoMODE_ASK       = 0.0;
   double mMarketinfoMODE_BID       = 0.0;
   double mMarketinfoMODE_POINT     = 0.0;
   double mMarketinfoMODE_STOPLEVEL = 0.0;

   //残高不足の場合は、発注しない
   if(AccountFreeMarginCheck(symbol, cmd, volume) < 0.0) {
//      printf( "[%d]COMM エラー 残高不足" , __LINE__);   
   
 //     return ERROR;
   }

   // スプレッドが広がりすぎている時は、発注しない。
   if(MathAbs(mMarketinfoMODE_ASK - mMarketinfoMODE_BID) > change_PiPS2Point(MAX_SPREAD_PIPS)) {
      printf( "[%d]COMM エラー 値幅が広すぎる" , __LINE__);   
   
      return ERROR;
   }

  
   //初期値設定
   string commentBuf = "";// comment欄は31バイト以上を設定すると空欄になるため、それを避ける。
   if(cmd == OP_BUY || cmd == OP_SELL) {
      mMarketinfoMODE_ASK = MarketInfo(symbol,MODE_ASK);
      mMarketinfoMODE_BID = MarketInfo(symbol,MODE_BID);
      mMarketinfoMODE_POINT = global_Points;
      mMarketinfoMODE_STOPLEVEL = change_PiPS2Point(global_StopLevel);
      //|   ※ 引数で渡された利確値、損切値が、０より大きい場合に限り、OrderSendのコメント欄に、<TP>・・・</TP><SL>・・・</SL>を追加する。
      if(takeprofit > 0.0) {
         commentBuf = "<T" + DoubleToStr(takeprofit, global_Digits) + "/T>" + comment;
         if(StringLen(commentBuf) > 30) {
            printf( "[%d]COMM エラー　commentの文字数が%d文字となり、31文字以上になるため、最初の30文字のみを利用します<" , __LINE__,StringLen(commentBuf));
            comment = StringSubstr(commentBuf,0,30);
         }
         else {
            comment = commentBuf;
         }
      }
      if(stoploss > 0.0) {
         commentBuf = "<S" + DoubleToStr(stoploss, global_Digits) + "/S>" + comment;
         if(StringLen(commentBuf) > 30) {
            printf( "[%d]COMM エラー　commentの文字数が%d文字となり、31文字以上になるため、最初の30文字のみを利用します<" , __LINE__,StringLen(commentBuf));
            comment = StringSubstr(commentBuf,0,30);
         }
         else {
            comment = commentBuf;
         }
      }

      
   }
   else {
      printf( "[%d]COMM エラー 発注時の価格等を取得できない" , __LINE__);   
      return ERROR;      
   }

   // takeprofitとstoplossを0.0として、OrderSendを実行する。
   // takeprofitとstoplosslへの変更は、OrderSend成功後にOrderModifyを使う。      
   ticket_num = OrderSend(symbol, cmd, volume, price, slippage, 0.0, 0.0, comment, magic, expiration, arrow_color);
   if(ticket_num <= 0) {  
      printf( "[%d]COMMエラー OrderSend失敗：：%s" , __LINE__,GetLastError());
      return ERROR_ORDERSEND;
   }
   else {
      // OrderSendの成功をメール送信
      string bufBuySell = "";
      if(cmd == OP_BUY) {
         bufBuySell = "ロング";         
      }
      else if(cmd == OP_SELL) {
         bufBuySell = "ショート";
      }
      datetime mailTime = convertToJapanTime();
      string strSubject = ""; // サブジェクト
      string strBody    = ""; // 本文
      
      strSubject = IntegerToString(AccountNumber()) + ":" + AccountServer() + "で、" + ">" + bufBuySell + "<を発注";
      strBody    = strBody + "サーバ　>" + AccountServer() + "<\n"; 
      strBody    = strBody + "口座番号>" + IntegerToString(AccountNumber()) + "<\n"; 
      strBody    = strBody + "売買区分>" + bufBuySell  + "<\n"; 
      strBody    = strBody + "約定日時>" + TimeToStr(mailTime) + "<\n"; 
      strBody    = strBody + "約定金額>" + DoubleToString(price, 8) + "<\n"; 
      strBody    = strBody + "コメント>" + comment + "<\n"; 
      strBody    = strBody + "==========" + comment + "<\n"; 
      strBody    = strBody + "4時間移動平均" + comment + "<\n"; 
      strBody    = strBody + TimeToString(iTime(symbol, PERIOD_H4, 1)) + ":" + DoubleToString(iMA(symbol, PERIOD_H4, 14 ,0,MODE_EMA,PRICE_CLOSE, 1))  + "<\n"; 
      strBody    = strBody + TimeToString(iTime(symbol, PERIOD_H4, 2)) + ":" + DoubleToString(iMA(symbol, PERIOD_H4, 14 ,0,MODE_EMA,PRICE_CLOSE, 2))  + "<\n"; 
      strBody    = strBody + TimeToString(iTime(symbol, PERIOD_H4, 3)) + ":" + DoubleToString(iMA(symbol, PERIOD_H4, 14 ,0,MODE_EMA,PRICE_CLOSE, 3))  + "<\n"; 
      strBody    = strBody + TimeToString(iTime(symbol, PERIOD_H4, 4)) + ":" + DoubleToString(iMA(symbol, PERIOD_H4, 14 ,0,MODE_EMA,PRICE_CLOSE, 4))  + "<\n"; 
      strBody    = strBody + TimeToString(iTime(symbol, PERIOD_H4, 5)) + ":" + DoubleToString(iMA(symbol, PERIOD_H4, 14 ,0,MODE_EMA,PRICE_CLOSE, 5))  + "<\n"; 
printf( "[%d]COMM メール送信内容（本文）：：%s" , __LINE__,strBody);
      SendMail(strSubject , strBody);
   }

   // 引数takeprofitとstoplossが0以下の時は、tpとslを設定しないで正常終了。
   if(takeprofit < 0.0 && stoploss < 0.0) {
      return ticket_num;
   }

   // 外部変数TP_PIPSとSL_PIPSが0未満の時は、tpとslを設定しないで正常終了。
   if(TP_PIPS < 0 && SL_PIPS < 0) {
      return ticket_num;
   }

   //
   // 以下は、引数takeprofitとstoplossを使った指値変更処理
   // 
   // ストップレベルを使って、takeprofitとstoplossが設定できなければ、0にする
   update_TPSL_with_StopLevel(cmd,     // 売買区分OP_SELL, OP_BUY
                              mMarketinfoMODE_ASK, // 判断時のASK
                              mMarketinfoMODE_BID, // 判断時のBID   
                              mMarketinfoMODE_STOPLEVEL, // 14 MODE_STOPLEVEL  //point単位でストップレベルを取得 https://buco-bianco.com/mql4-marketinfo-function/
                              takeprofit, // 出力：利確値候補を渡す。売買区分とストップレベルを考慮して、設定可能であればそのままの値を返し、設定不可能であれば0を返す。
                              stoploss    // 出力：利確値候補を渡す。売買区分とストップレベルを考慮して、設定可能であればそのままの値を返し、設定不可能であれば0を返す。
                                );
/*
printf( "[%d]COMM Ordersend5 で設定する　tp=%s   sl=%s" , __LINE__,
DoubleToStr(takeprofit, global_Digits),
DoubleToStr(stoploss, global_Digits)
);
*/ 
   // 引数takeprofitとstoplossが共に0の場合は、変更は必要ない。
   if(takeprofit == 0.0 && stoploss == 0.0) {
   }
   else {
      // 修正する取引を選択する。
      if(OrderSelect(ticket_num, SELECT_BY_TICKET) == true) {
         mFlag =OrderModify(ticket_num, price, stoploss, takeprofit, 0, arrow_color);
         if(mFlag != true) {
            printf( "[%d]COMMエラー OrderModify：：%s" , __LINE__,GetLastError());
            return ERROR_ORDERSEND;
         }
         else {
            return ticket_num;
         }
      }
      else {
         printf( "[%d]COMMエラー OrderModify用のOrderSelect失敗" , __LINE__);
         return ERROR_ORDERSEND;
      }
   }
   
   return ticket_num;
}



// ストップレベルを使って、takeprofitとstoplossが設定できなければ、0にする
// ロングの利確takeprofitは、その時のASK＋ストップレベルより大きくなくてはならない。
// ロングの損切stoploss　は、その時のBID-ストップレベルより小さくなくてはならない。
// 参考資料：https://toushi-strategy.com/mt4/stoplevel/
// ショートの利確takeprofitは、その時のBID-ストップレベルより小さくなくてはならない。
// ショートの損切stoplossは、その時のASK+ストップレベルより大きくなくてはならない。
// 参考資料：https://toushi-strategy.com/mt4/stoplevel/　　から、推測。
void update_TPSL_with_StopLevel(int    mBuySell,     // 売買区分OP_SELL, OP_BUY
                                double mMarketinfoMODE_ASK, // 判断時のASK
                                double mMarketinfoMODE_BID, // 判断時のBID
                                double mMarketinfoMODE_STOPLEVEL, // 14 MODE_STOPLEVEL  //point単位でストップレベルを取得 https://buco-bianco.com/mql4-marketinfo-function/
                                double &mTakeprofit, // 出力：利確値候補を渡す。売買区分とストップレベルを考慮して、設定可能であればそのままの値を返し、設定不可能であれば0を返す。
                                double &mStoploss    // 出力：利確値候補を渡す。売買区分とストップレベルを考慮して、設定可能であればそのままの値を返し、設定不可能であれば0を返す。
                                ) {
   // ロングの利確takeprofitは、その時のASK＋ストップレベルより大きくなくてはならない。
   // ロングの損切stoploss　は、その時のBID-ストップレベルより小さくなくてはならない。
   // 参考資料：https://toushi-strategy.com/mt4/stoplevel/
   //
   if(mBuySell == OP_BUY) {
      // takeprofitの判断。
/*
printf( "[%d]COMM 買いの時、　mTakeprofit=%s mMarketinfoMODE_ASK=%s mMarketinfoMODE_STOPLEVEL=%s" , __LINE__,
DoubleToStr(mTakeprofit, global_Digits),
DoubleToStr(mMarketinfoMODE_ASK, global_Digits),
DoubleToStr(mMarketinfoMODE_STOPLEVEL, global_Digits)
);
*/         
      if(NormalizeDouble(mTakeprofit, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL, global_Digits)) {
         // mTakeprofitは更新しない。
      }
      else {
         // mTakeprofitを0.0クリアする。
         mTakeprofit = 0.0;
      }
            
      if(NormalizeDouble(mStoploss, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL, global_Digits)) {
         // mStoplossは更新しない。
      }
      else {
         // mStoplossを0.0クリアする。
         mStoploss = 0.0;
      }
   }

   // ショートの利確takeprofitは、その時のBID-ストップレベルより小さくなくてはならない。
   // ショートの損切stoplossは、その時のASK+ストップレベルより大きくなくてはならない。
   // 参考資料：https://toushi-strategy.com/mt4/stoplevel/　　から、推測。
   if(mBuySell == OP_SELL) {
      // takeprofitの判断。
      if(NormalizeDouble(mTakeprofit, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL, global_Digits)) {
         // mTakeprofitは更新しない。
      }
      else {
         // mTakeprofitを0.0クリアする。
         mTakeprofit = 0.0;
      }
      if(NormalizeDouble(mStoploss, global_Digits) > NormalizeDouble(mMarketinfoMODE_BID + mMarketinfoMODE_STOPLEVEL, global_Digits)) {
         // mStoplossは更新しない。
      }
      else {
         // mStoplossを0.0クリアする。
         mStoploss = 0.0;
      }
   }
}



//+------------------------------------------------------------------+
//|   実取引の送信
//|   ※ 残高不足の場合は、発注しない
//|   ※ スプレッドが広がりすぎている時は、発注しない
//|   ※ 引数のdouble stoploss, double takeprofitが、発注制限値を満たしていなければ、発注しない
//|   入力：OrderSend関数に必要な引数
//|   出力：チケットナンバー                                       |
//+------------------------------------------------------------------+
int mOrderSend4(string symbol, int cmd, double volume, double price, int slippage, double stoploss, double takeprofit, string comment=NULL, int magic=0, datetime expiration=0, color arrow_color=CLR_NONE) {
   bool mFlag = false;
   int Index = 0;
   int ticket_num =-1;
   double ATR_1 = 0.0;
   double mOpenPrice = 0.0;  // 設定中の約定値
   double mTP = 0.0;         // 設定中の利確値
   double mSL = 0.0;         // 設定中の損切値
   double mTP4Modify = 0.0;  // 変更先の利確値
   double mSL4Modify = 0.0;  // 変更先の損切値

   double mMarketinfoMODE_ASK       = 0.0;
   double mMarketinfoMODE_BID       = 0.0;
   double mMarketinfoMODE_POINT     = 0.0;
   double mMarketinfoMODE_STOPLEVEL = 0.0;

   //残高不足の場合は、発注しない
   if(AccountFreeMarginCheck(symbol, cmd, volume) < 0.0) {
      return ERROR;
   }

   // スプレッドが広がりすぎている時は、発注しない。
   if(MathAbs(mMarketinfoMODE_ASK - mMarketinfoMODE_BID) > change_PiPS2Point(MAX_SPREAD_PIPS)) {
      return ERROR;
   }

  //初期値設定
   if(cmd == OP_BUY || cmd == OP_SELL) {
      mMarketinfoMODE_ASK = MarketInfo(symbol,MODE_ASK);
      mMarketinfoMODE_BID = MarketInfo(symbol,MODE_BID);
      mMarketinfoMODE_POINT = global_Points;
      mMarketinfoMODE_STOPLEVEL = global_StopLevel;
   }
   else {
      printf( "[%d]COMM エラー 発注時の価格等を取得できない" , __LINE__);   
      return ERROR;      
   }

   // 発注制限値を計算
   double long_tp_MIN  = NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   double long_sl_MAX  = NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   double short_tp_MAX = NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   double short_sl_MIN = NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   




   
   // 引数のdouble stoploss, double takeprofitが、発注制限値を満たしていなければ、発注しない
   if(cmd == OP_BUY) {
      // takeprofitとstoploss各々で、値が設定されていながら、発注できない値であれば、発注制限値違反のためロングを発注しない。
      if(takeprofit > 0.0 && takeprofit <= long_tp_MIN) {
         printf( "[%d]COMM エラー 利確値が発注制限値違反のためロングを発注しない。takeprofit=%s long_tp_MIN=%s以上でなくてはならない。 " , __LINE__,
                  DoubleToStr(takeprofit,  global_Digits),
                  DoubleToStr(long_tp_MIN, global_Digits)
               );   
         return ERROR;  
      }
      if(stoploss > 0.0 && stoploss >= long_sl_MAX) {
         printf( "[%d]COMM エラー 損切値が発注制限値違反のためロングを発注しない。stoploss=%s long_sl_MAX=%s以下でなくてはならない。 " , __LINE__,
                  DoubleToStr(stoploss,  global_Digits),
                  DoubleToStr(long_sl_MAX, global_Digits)
               );   
         return ERROR;  
      }
   }
   else if(cmd == OP_SELL) {
      // takeprofitとstoploss各々で、値が設定されていながら、発注できない値であれば、発注制限値違反のためロングを発注しない。
      if(takeprofit > 0.0 && takeprofit >= short_tp_MAX) {
         printf( "[%d]COMM エラー 利確値が発注制限値違反のためショートを発注しない。takeprofit=%s short_tp_MAX=%s以下でなくてはならない。 " , __LINE__,
                  DoubleToStr(stoploss,  global_Digits),
                  DoubleToStr(short_tp_MAX, global_Digits)
               );   
         return ERROR;  
      }
      if(stoploss > 0.0 && stoploss <= short_sl_MIN) {
         printf( "[%d]COMM エラー 損切値が発注制限値違反のためショートを発注しない。stoploss=%s short_sl_MIN=%s以上でなくてはならない。 " , __LINE__,
                  DoubleToStr(stoploss,  global_Digits),
                  DoubleToStr(short_sl_MIN, global_Digits)
               );   
         return ERROR;  
      }
   }

   
   // takeprofitとstoplossを0.0として、OrderSendを実行する。
   // takeprofitとstoplosslへの変更は、OrderSend成功後にOrderModifyを使う。      
   
   
   ticket_num = OrderSend(symbol, cmd, volume, price, slippage, 0.0, 0.0, comment, magic, expiration, arrow_color);
   if(ticket_num <= 0) {  
      printf( "[%d]COMMエラー OrderSend失敗：：%s" , __LINE__,GetLastError());
      return ERROR_ORDERSEND;
   }
   
   // 引数takeprofitとstoplossが0以下の時は、tpとslを設定しないで正常終了。
   if(takeprofit <= 0.0 && stoploss <= 0.0) {
      return ticket_num;
   }

   // 外部変数TP_PIPSとSL_PIPSが0未満の時は、tpとslを設定しないで正常終了。
   if(TP_PIPS < 0 && SL_PIPS < 0) {
      return ticket_num;
   }

   //
   // 以下は、引数takeprofitとstoplossを使った指値変更処理
   // 

   // 修正する取引を選択する。
   if(OrderSelect(ticket_num, SELECT_BY_TICKET) == true) {
      mFlag =OrderModify(ticket_num, price, stoploss, takeprofit, 0, arrow_color);
      if(mFlag != true) {
         printf( "[%d]COMMエラー OrderModify：：%s" , __LINE__,GetLastError());
         return ERROR_ORDERSEND;
      }
      else {
         return ticket_num;
      }
   }
   else {
      printf( "[%d]COMMエラー OrderModify用のOrderSelect失敗" , __LINE__);
      return ERROR_ORDERSEND;
   }
   /*
   for(int ii = OrdersTotal() -1; ii >= 0;ii--) {
      if(OrderSelect(ii, SELECT_BY_POS, MODE_TRADES) == true && 
         OrderMagicNumber() == magic &&
         OrderTicket() == ticket_num) {   
            mOpenPrice = NormalizeDouble(OrderOpenPrice(), global_Digits);
            mTP        = NormalizeDouble(OrderTakeProfit(), global_Digits);
            mSL        = NormalizeDouble(OrderStopLoss(), global_Digits);
            break;
      }
   }
   */
}

int mOrderSend4_NOCHECK(string symbol, int cmd, double volume, double price, int slippage, double stoploss, double takeprofit, string comment=NULL, int magic=0, datetime expiration=0, color arrow_color=CLR_NONE) {
   bool mFlag = false;
   int Index = 0;
   int ticket_num =-1;
   double ATR_1 = 0.0;
   double mOpenPrice = 0.0;  // 設定中の約定値
   double mTP = 0.0;         // 設定中の利確値
   double mSL = 0.0;         // 設定中の損切値
   double mTP4Modify = 0.0;  // 変更先の利確値
   double mSL4Modify = 0.0;  // 変更先の損切値

   double mMarketinfoMODE_ASK       = 0.0;
   double mMarketinfoMODE_BID       = 0.0;
   double mMarketinfoMODE_POINT     = 0.0;
   double mMarketinfoMODE_STOPLEVEL = 0.0;

   //残高不足の場合は、発注しない
   if(AccountFreeMarginCheck(symbol, cmd, volume) < 0.0) {
      printf( "[%d]COMM エラー 残高不足のため、発注せず。" , __LINE__);   
      return ERROR_MARGINSHORT;
   }
/* NOCHECKのため、チェックしない
   // スプレッドが広がりすぎている時は、発注しない。
   if(MathAbs(mMarketinfoMODE_ASK - mMarketinfoMODE_BID) > global_Points * MAX_SPREAD_PIPS) {
      return ERROR;
   }
*/
  //初期値設定
   if(cmd == OP_BUY || cmd == OP_SELL) {
      mMarketinfoMODE_ASK = MarketInfo(symbol,MODE_ASK);
      mMarketinfoMODE_BID = MarketInfo(symbol,MODE_BID);
      mMarketinfoMODE_POINT = change_Point2PIPS(global_Points);
      mMarketinfoMODE_STOPLEVEL = global_StopLevel;
   }
   else {
      printf( "[%d]COMM エラー 発注時の価格等を取得できない" , __LINE__);   
      return ERROR;      
   }

/* NOCHECKのため、チェックしない
   // 発注制限値を計算
   double long_tp_MIN  = NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   double long_sl_MAX  = NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   double short_tp_MAX = NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   double short_sl_MIN = NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   // 引数のdouble stoploss, double takeprofitが、発注制限値を満たしていなければ、発注しない
   if(cmd == OP_BUY) {
      // takeprofitとstoploss各々で、値が設定されていながら、発注できない値であれば、発注制限値違反のためロングを発注しない。
      if(takeprofit > 0.0 && takeprofit <= long_tp_MIN) {
         printf( "[%d]COMM エラー 利確値が発注制限値違反のためロングを発注しない。takeprofit=%s long_tp_MIN=%s以上でなくてはならない。 " , __LINE__,
                  DoubleToStr(takeprofit,  global_Digits),
                  DoubleToStr(long_tp_MIN, global_Digits)
               );   
         return ERROR;  
      }
      if(stoploss > 0.0 && stoploss >= long_sl_MAX) {
         printf( "[%d]COMM エラー 損切値が発注制限値違反のためロングを発注しない。stoploss=%s long_sl_MAX=%s以下でなくてはならない。 " , __LINE__,
                  DoubleToStr(stoploss,  global_Digits),
                  DoubleToStr(long_sl_MAX, global_Digits)
               );   
         return ERROR;  
      }
   }
   else if(cmd == OP_SELL) {
      // takeprofitとstoploss各々で、値が設定されていながら、発注できない値であれば、発注制限値違反のためロングを発注しない。
      if(takeprofit > 0.0 && takeprofit >= short_tp_MAX) {
         printf( "[%d]COMM エラー 利確値が発注制限値違反のためショートを発注しない。takeprofit=%s short_tp_MAX=%s以下でなくてはならない。 " , __LINE__,
                  DoubleToStr(stoploss,  global_Digits),
                  DoubleToStr(short_tp_MAX, global_Digits)
               );   
         return ERROR;  
      }
      if(stoploss > 0.0 && stoploss <= short_sl_MIN) {
         printf( "[%d]COMM エラー 損切値が発注制限値違反のためショートを発注しない。stoploss=%s short_sl_MIN=%s以上でなくてはならない。 " , __LINE__,
                  DoubleToStr(stoploss,  global_Digits),
                  DoubleToStr(short_sl_MIN, global_Digits)
               );   
         return ERROR;  
      }
   }
*/
   
   // takeprofitとstoplossを0.0として、OrderSendを実行する。
   // takeprofitとstoplosslへの変更は、OrderSend成功後にOrderModifyを使う。      
   
   ticket_num = OrderSend(symbol, cmd, volume, price, slippage, 0.0, 0.0, comment, magic, expiration, arrow_color);
   if(ticket_num <= 0) {  
      printf( "[%d]COMMエラー OrderSend失敗：：open=%s mMarketinfoMODE_BID=%s mMarketinfoMODE_ASK=%s" , __LINE__,
         DoubleToStr(price, global_Digits),
         DoubleToStr(mMarketinfoMODE_BID, global_Digits),
         DoubleToStr(mMarketinfoMODE_ASK, global_Digits)
      );
      
      return ERROR_ORDERSEND;
   }
   
   // 引数takeprofitとstoplossが0以下の時は、tpとslを設定しないで正常終了。
   if(takeprofit <= 0.0 && stoploss <= 0.0) {
      return ticket_num;
   }

   // 外部変数TP_PIPSとSL_PIPSが0未満の時は、tpとslを設定しないで正常終了。
   if(TP_PIPS < 0 && SL_PIPS < 0) {
      return ticket_num;
   }

   //
   // 以下は、引数takeprofitとstoplossを使った指値変更処理
   // 

   // 修正する取引を選択する。
   if(OrderSelect(ticket_num, SELECT_BY_TICKET) == true) {
      mFlag = OrderModify(ticket_num, price, stoploss, takeprofit, 0, arrow_color);
      if(mFlag != true) {
         printf( "[%d]COMMエラー OrderModify：：open=%s SL=%s TP=%s" , __LINE__,
            DoubleToStr(price, global_Digits),
            DoubleToStr(stoploss, global_Digits),
            DoubleToStr(takeprofit, global_Digits)
         );
         return ERROR_ORDERMODIFY;
      }
      else {
         return ticket_num;
      }
   }
   else {
      printf( "[%d]COMMエラー OrderModify用のOrderSelect失敗" , __LINE__);
      return ERROR_ORDERSEND;
   }
   /*
   for(int ii = OrdersTotal() -1; ii >= 0;ii--) {
      if(OrderSelect(ii, SELECT_BY_POS, MODE_TRADES) == true && 
         OrderMagicNumber() == magic &&
         OrderTicket() == ticket_num) {   
            mOpenPrice = NormalizeDouble(OrderOpenPrice(), global_Digits);
            mTP        = NormalizeDouble(OrderTakeProfit(), global_Digits);
            mSL        = NormalizeDouble(OrderStopLoss(), global_Digits);
            break;
      }
   }
   */
}
/*
int org20220919mOrderSend4(string symbol, int cmd, double volume, double price, int slippage, double stoploss, double takeprofit, string comment=NULL, int magic=0, datetime expiration=0, color arrow_color=CLR_NONE) {
   bool mFlag = false;
   int Index = 0;
   int ticket_num =-1;
   double ATR_1 = 0.0;
   double mOpenPrice = 0.0;  // 設定中の約定値
   double mTP = 0.0;         // 設定中の利確値
   double mSL = 0.0;         // 設定中の損切値
   double mTP4Modify = 0.0;  // 変更先の利確値
   double mSL4Modify = 0.0;  // 変更先の損切値

   double mMarketinfoMODE_ASK       = 0.0;
   double mMarketinfoMODE_BID       = 0.0;
   double mMarketinfoMODE_POINT     = 0.0;
   double mMarketinfoMODE_STOPLEVEL = 0.0;

   //残高不足の場合は、発注しない
   if(AccountFreeMarginCheck(symbol, cmd, volume) < 0.0) {
      return ERROR;
   }

   // スプレッドが広がりすぎている時は、発注しない。
   if(MathAbs(mMarketinfoMODE_ASK - mMarketinfoMODE_BID) > global_Points * MAX_SPREAD_PIPS) {
      return ERROR;
   }

  //初期値設定
   if(cmd == OP_BUY || cmd == OP_SELL) {
      mMarketinfoMODE_ASK = MarketInfo(symbol,MODE_ASK);
      mMarketinfoMODE_BID = MarketInfo(symbol,MODE_BID);
      mMarketinfoMODE_POINT = global_Points;
      mMarketinfoMODE_STOPLEVEL = global_StopLevel;
   }
   else {
      printf( "[%d]COMM エラー 発注時の価格等を取得できない" , __LINE__);   
      return ERROR;      
   }

   // 発注制限値を計算
   double long_tp_MIN  = NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   double long_sl_MAX  = NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   double short_tp_MAX = NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   double short_sl_MIN = NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   // 引数のdouble stoploss, double takeprofitが、発注制限値を満たしていなければ、発注しない
   if(cmd == OP_BUY) {
      if(takeprofit <= long_tp_MIN || stoploss >= long_sl_MAX) {
         printf( "[%d]COMM エラー 発注制限値違反のためロングを発注しない。takeprofit=%s long_tp_MIN=%s以上でなくてはならない。 stoploss=%s long_sl_MAX=%s以下でなくてはならない" , __LINE__,
                  DoubleToStr(takeprofit,  global_Digits),
                  DoubleToStr(long_tp_MIN, global_Digits),
                  DoubleToStr(stoploss,    global_Digits),
                  DoubleToStr(long_sl_MAX, global_Digits)
               );   
         return ERROR;  
      }
   }
   else if(cmd == OP_SELL) {
      if(takeprofit >= short_tp_MAX || stoploss <= short_sl_MIN) {
         printf( "[%d]COMM エラー 発注制限値違反のためショートを発注しない。takeprofit=%s long_tp_MAX=%s以下でなくてはならない。 stoploss=%s short_tp_MIN=%s以上でなくてはならない" , __LINE__,
                  DoubleToStr(takeprofit,   global_Digits),
                  DoubleToStr(short_tp_MAX,  global_Digits),
                  DoubleToStr(stoploss,     global_Digits),
                  DoubleToStr(short_sl_MIN, global_Digits)
               );   
         return ERROR;  
      }
   }

   if(takeprofit > 0.0) {
      comment = comment + "<TP>" + DoubleToStr(takeprofit, global_Digits) + "</TP>";
   }
   if(stoploss > 0.0) {
      comment = comment + "<SL>" + DoubleToStr(stoploss, global_Digits) + "</SL>";
   }
printf( "[%d]COMM commentにTPとSLを埋め込み中>%s<" , __LINE__,comment);
   
   // takeprofitとstoplossを0.0として、OrderSendを実行する。
   // takeprofitとstoplosslへの変更は、OrderSend成功後にOrderModifyを使う。      
   ticket_num = OrderSend(symbol, cmd, volume, price, slippage, 0.0, 0.0, comment, magic, expiration, arrow_color);
   if(ticket_num <= 0) {  
      printf( "[%d]COMMエラー OrderSend失敗：：%s" , __LINE__,GetLastError());
      return ERROR_ORDERSEND;
   }
   
   // 引数takeprofitとstoplossが0以下の時は、tpとslを設定しないで正常終了。
   if(takeprofit <= 0.0 && stoploss <= 0.0) {
      return ticket_num;
   }

   // 外部変数TP_PIPSとSL_PIPSが0未満の時は、tpとslを設定しないで正常終了。
   if(TP_PIPS < 0 && SL_PIPS < 0) {
      return ticket_num;
   }

   //
   // 以下は、引数takeprofitとstoplossを使った指値変更処理
   // 

   // 修正する取引を選択する。
   for(int ii = OrdersTotal() -1; ii >= 0;ii--) {
      if(OrderSelect(ii, SELECT_BY_POS, MODE_TRADES) == true && 
         OrderMagicNumber() == magic &&
         OrderTicket() == ticket_num) {   
            mOpenPrice = NormalizeDouble(OrderOpenPrice(), global_Digits);
            mTP        = NormalizeDouble(OrderTakeProfit(), global_Digits);
            mSL        = NormalizeDouble(OrderStopLoss(), global_Digits);
            break;
      }
   }

   if(mOpenPrice <= 0.0) {
      printf( "[%d]COMMエラー オープン値の設定に失敗：：マジックナンバー：%s TicketNO:%s" , __LINE__,IntegerToString(magic), IntegerToString(ticket_num));
      return ERROR;
   }
   
   // ロングの利益確定最小値＝これより大きな利確値のみ設定可能
   if(cmd == OP_BUY)  {
      if(takeprofit > long_tp_MIN) {
         mTP4Modify = NormalizeDouble(takeprofit, global_Digits);
      }
      else {
         mTP4Modify = 0.0;
      }
   }

   // ロングの損失確定最大値＝これより小さな損切値のみ設定可能
   if(cmd == OP_BUY)  {
      if(stoploss < long_sl_MAX) {
         mSL4Modify = NormalizeDouble(stoploss, global_Digits);
      }
      else {
         mSL4Modify = 0.0;
      }
   }

   // ショートの利益確定最大値＝これより小さな利確値のみ設定可能
   if(cmd == OP_SELL)  {
      if(takeprofit < short_tp_MAX) {
         mTP4Modify = NormalizeDouble(takeprofit, global_Digits);
      }
      else {
         mTP4Modify = 0.0;
      }
   }

   // ショートの損失確定最小値＝これより大きな損切値のみ設定可能
   if(cmd == OP_SELL)  {
      if(stoploss > short_sl_MIN) {
         mSL4Modify = NormalizeDouble(stoploss, global_Digits);
      }
      else {
         mSL4Modify = 0.0;
      }
   }

   // ロングとショートの利確、損切が、設定値と変更先の全てが一致している時はModifyしない。
   if(mTP4Modify == mTP && mSL4Modify == mSL) {
      // 変更が無いため、OrderModifyをしない
   }
   else {
      mFlag =OrderModify(ticket_num, mOpenPrice, mSL4Modify, mTP4Modify, 0, arrow_color);
      if(mFlag != true) {
         printf( "[%d]COMMエラー OrderModify：：%s" , __LINE__,GetLastError());
      }
   }
   
   if(ticket_num > 0) {
      return ticket_num;
   }
   else {
      printf( "[%d]COMMエラー 発注失敗" , __LINE__,GetLastError());
      return ERROR;                     
   }	
}

*/
/*
int orgmOrderSend4(string symbol, int cmd, double volume, double price, int slippage, double stoploss, double takeprofit, string comment=NULL, int magic=0, datetime expiration=0, color arrow_color=CLR_NONE) {
   bool mFlag = false;
   int Index = 0;
   int ticket_num =-1;
   double ATR_1 = 0.0;
   double mOpen4Modify = 0.0;
   double mTP4Modify = 0.0;
   double mSL4Modify = 0.0;

   double mMarketinfoMODE_ASK = 0.0;
   double mMarketinfoMODE_BID = 0.0;
   double mMarketinfoMODE_POINT = 0.0;
   double mMarketinfoMODE_STOPLEVEL = 0.0;

  //初期値設定
   if(cmd == OP_BUY || cmd == OP_SELL) {
      mMarketinfoMODE_ASK = MarketInfo(symbol,MODE_ASK);
      mMarketinfoMODE_BID = MarketInfo(symbol,MODE_BID);
      mMarketinfoMODE_POINT = global_Points;
      mMarketinfoMODE_STOPLEVEL = global_StopLevel;
   }
   else {
printf( "[%d]COMM エラー" , __LINE__);   
      return ERROR;      
   }

   //残高不足の場合は、エントリーしない
   if(AccountFreeMarginCheck(symbol, cmd, volume) < 0.0) {
      return ERROR;
   }

   // スプレッドが広がりすぎている時は、エントリーしない。
   if(MathAbs(mMarketinfoMODE_ASK - mMarketinfoMODE_BID) > global_Points * MAX_SPREAD_PIPS) {
 
      return ERROR;
   }
   

   if(takeprofit > 0.0) {
      comment = comment + "<TP>" + DoubleToStr(takeprofit, global_Digits) + "</TP>";
   }
   if(stoploss > 0.0) {
      comment = comment + "<SL>" + DoubleToStr(stoploss, global_Digits) + "</SL>";
   }
printf( "[%d]COMM commentにTPとSLを埋め込み中>%s<" , __LINE__,comment);

   // takeprofitとstoplossを0.0として、OrderSendを実行する。
   // takeprofitとstoplosslへの変更は、OrderSend成功後にOrderModifyを使う。  
   ticket_num = OrderSend(symbol, cmd, volume, price, slippage, 0.0, 0.0, comment, magic, expiration, arrow_color);
   if(ticket_num <= 0) {  
      printf( "[%d]COMMエラー OrderSend失敗：：%s" , __LINE__,GetLastError());
      return ERROR_ORDERSEND;
   }
   
   // 引数takeprofitとstoplossが0以下の時は、tpとslを設定しないで正常終了。
   if(takeprofit <= 0.0 && stoploss <= 0.0) {
      return ticket_num;
   }

   // 外部変数TP_PIPSとSL_PIPSが0未満の時は、tpとslを設定しないで正常終了。
   if(TP_PIPS < 0 && SL_PIPS < 0) {
      return ticket_num;
   }

   //
   // 以下は、引数takeprofitとstoplossを使った指値変更処理
   // 

   // 修正する取引を選択する。
   for(int ii = OrdersTotal() -1; ii >= 0;ii--) {
      if(OrderSelect(ii, SELECT_BY_POS, MODE_TRADES) == true && 
         OrderMagicNumber() == magic &&
         OrderTicket() == ticket_num) {   
            mOpen4Modify = OrderOpenPrice();
            mTP4Modify   = OrderTakeProfit();
            mSL4Modify   = OrderStopLoss();
            break;
      }
   }

   if(mOpen4Modify <= 0.0) {
      printf( "[%d]COMMエラー オープン値の設定に失敗：：マジックナンバー：%s TicketNO:%s" , __LINE__,IntegerToString(magic), IntegerToString(ticket_num));
      return ERROR;
   }
   
   
   // ロングの利確takeprofitは、その時のASK＋ストップレベルより大きくなくてはならない。
   // ロングの損切stoploss　は、その時のBID-ストップレベルより小さくなくてはならない。
   // 参考資料：https://toushi-strategy.com/mt4/stoplevel/
   //
   if(cmd == OP_BUY) {

      // takeprofitとstoploss両方が条件を満たす場合。
      if(takeprofit > mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT &&
         stoploss   < mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
         mFlag =OrderModify(ticket_num, mOpen4Modify, stoploss, takeprofit, 0, arrow_color);
         if(mFlag != true) {
            printf( "[%d]COMMエラー OrderModify：：%s" , __LINE__,GetLastError());
         }
      }
      
      // takeprofitのみが条件を満たす場合。   
      if(takeprofit > mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT &&
         stoploss >=  mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
         mFlag =OrderModify(ticket_num, mOpen4Modify, mSL4Modify, takeprofit, 0, arrow_color);
         if(mFlag != true) {
            printf( "[%d]COMMエラー OrderModify：：%s" , __LINE__,GetLastError());
         }
      }
      // stoplossのみが条件を満たす場合。   
      else if(
         takeprofit <= mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT &&
         stoploss   <  mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
         mFlag =OrderModify(ticket_num, mOpen4Modify, stoploss, mTP4Modify, 0, arrow_color);
         if(mFlag != true) {
            printf( "[%d]COMMエラー OrderModify：：%s" , __LINE__,GetLastError());
         }
      }
      // takeprofitとstoploss両方が条件を満たさない場合は、何もしない。
      else {
      }
   }  // ロングの場合の指値変更処理は、ここまで。

   // ショートの利確takeprofitは、その時のBID-ストップレベルより小さくなくてはならない。
   // ショートの損切stoplossは、その時のASK+ストップレベルより大きくなくてはならない。
   // 参考資料：https://toushi-strategy.com/mt4/stoplevel/　　から、推測。
   if(cmd == OP_SELL) {
      // takeprofitとstoploss両方が条件を満たす場合。
      if(takeprofit < mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT &&
         stoploss > mMarketinfoMODE_BID + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
         mFlag =OrderModify(ticket_num, mOpen4Modify, stoploss, takeprofit, 0, arrow_color);
         if(mFlag != true) {
            printf( "[%d]COMMエラー OrderModify：：%s" , __LINE__,GetLastError());
         }
      }

      // takeprofitのみが条件を満たす場合。   
      else if(
         takeprofit <  mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT &&
         stoploss   <= mMarketinfoMODE_BID + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {
         
         mFlag =OrderModify(ticket_num, mOpen4Modify,mSL4Modify, takeprofit, 0, arrow_color);
         if(mFlag != true) {
            printf( "[%d]COMMエラー OrderModify：：%s" , __LINE__,GetLastError());
         }
      }

      // stoplossのみが条件を満たす場合。   
      else if(
         takeprofit >= mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT &&
         stoploss   >  mMarketinfoMODE_BID + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT) {

         mFlag =OrderModify(ticket_num, mOpen4Modify, stoploss, mTP4Modify, 0, arrow_color);    
         if(mFlag != true) {
            printf( "[%d]COMMエラー OrderModify：：%s" , __LINE__,GetLastError());
         }
      }
      // takeprofitとstoploss両方が条件を満たさない場合は、何もしない。
      else {
      }
   }
   
   if(ticket_num > 0) {
      return ticket_num;
   }
   else {
      printf( "[%d]COMMエラー 発注失敗" , __LINE__,GetLastError());
      return ERROR;                     
   }	
}

*/

/* 20221227 トレーディングラインを使った関数のため、COMMONとTRADINGLINEをincludeした環境で定義するのが正しい。
//+--------------------------------------------------------------------------+
//|   実取引の送信前に、取引時価格が取引可能価格帯にあるかを判断する関数judge_Tradable_Priceを |
//|   呼び出す版                                                               |  
//|   入力：OrderSend関数に必要な引数                                             |
//|   出力：チケットナンバー。ERROR_ORDERSEND、ERROR_ORDERSEND_TRADELINE               |
//+--------------------------------------------------------------------------+
int mOrderSend4_with_TradableLines(string symbol, int cmd, double volume, double price, int slippage, double stoploss, double takeprofit, string comment, int magic, datetime expiration, color arrow_color) {
   bool flagTradable = false;
   int  ticket_num   = -1;
  
   if(cmd == OP_BUY) {
//printf( "[%d]COM 時間測定　judge_Tradable_Price　buy　開始" , __LINE__);
   
      flagTradable = judge_Tradable_Price(magic, BUY_SIGNAL, price);
//printf( "[%d]COM 時間測定　judge_Tradable_Price　buy　終了" , __LINE__);
   }
   else if(cmd == OP_SELL) {
//printf( "[%d]COM 時間測定　judge_Tradable_Price　sell　開始" , __LINE__);
   
      flagTradable = judge_Tradable_Price(magic, SELL_SIGNAL, price);
//printf( "[%d]COM 時間測定　judge_Tradable_Price　sell　終了" , __LINE__);
   }
   else {
      return ticket_num;
   }
   
   // 関数を実行した時点のAskとBidが、取引可能な価格帯にある場合にのみ、mOrderSend4を実行する。
   if(flagTradable == true) { 
      ticket_num = mOrderSend4(symbol, cmd, volume, price, slippage, stoploss, takeprofit, comment, magic, expiration, Red);	
   }
   else {
      ticket_num = ERROR_ORDERSEND_TRADELINE;
   }
   
   return ticket_num;

}
*/


//
//余力を確認する関数
// 引数mLotsで取引した際、引数mLimitMarginを下回ることになったらfalse、取引してもmLimitMarginを下回らなかったらtrue
//
bool checkMargin(string mSymbol, int mBuySell, double mLots, double mLimitMargin) {
//mBuySell = BUY/SELL
//mLots    = 取引予定数量
//mLimitMargin = 維持率の制限値。これ以下の維持率になる場合はfalse

   //引数のチェック
   if( (mBuySell != OP_BUY && mBuySell != OP_SELL) ||
       (mLots <= 0.0) ||
       (mLimitMargin < 100.0) ){
 //printf( "[%d]COMM" , __LINE__);
       
        return false;
   }

   // 指定した引数mLotsでmBuySellエントリーした場合に、残る余剰証拠金
   double mAccountFreeMarginCheck = AccountFreeMarginCheck(mSymbol, mBuySell , mLots);
// printf( "[%d]COMM  mAccountFreeMarginCheck=%s" , __LINE__, DoubleToStr(mAccountFreeMarginCheck));
   
   if(mAccountFreeMarginCheck <= 0.0) {
      printf( "[%d]COMMエラー 残金が不足するため、新規エントリーできない。" , __LINE__);
      return false;
   }
if(ShowTestMsg == true) printf( "[%d]テストCOMMON mAccountFreeMargin=%s 残る余剰証拠金AccountFreeMarginCheck=%s" , __LINE__, 
         DoubleToStr(AccountFreeMargin()), DoubleToStr(mAccountFreeMarginCheck) );
         
            
   // 必要証拠金
   double mAccountMargin = AccountInfoDouble(ACCOUNT_MARGIN);
// printf( "[%d]COMM  mAccountMargin=%s" , __LINE__, DoubleToStr(mAccountMargin));
   
   if(mAccountMargin <= 0.0) {
      //バックテスト時はAccountInfoDoubleが、0になるため、その当時の価格から必要証拠金を推定する。
      mAccountMargin = getAccountInfoDouble();
//  printf( "[%d]COMM  mAccountMargin=%s" , __LINE__, DoubleToStr(mAccountMargin));
     
      // 推定も失敗した場合はエラーとする。
      if(mAccountMargin <= 0.0) {
         printf( "[%d]COMMエラー 必要証拠金の取得エラー。" , __LINE__);
         return false;
      }
   }
   
   //取引した場合の証拠金維持率=余剰証拠金 / 必要証拠金額*100
   double mAccountMarginLevel = mAccountFreeMarginCheck / (mAccountMargin * mLots)* 100;
   // 返り値を判定する。
// printf( "[%d]COMM  mAccountMarginLevel=%s  mLimitMargin%s" , __LINE__, DoubleToStr(mAccountMarginLevel), DoubleToStr(mLimitMargin));
   
   if(mAccountMarginLevel >= mLimitMargin) {
      return true;
   }

   return false;
   
}

double getAccountInfoDouble() {
   double mClose = iClose(global_Symbol, 1, 0);
   double digits = global_Digits;
   double mLotSize = global_LotSize;
   double mLev = AccountLeverage();
   double mRet = 0.0; //推定した証拠金

   if(ShowTestMsg == true) printf( "[%d]テストCOMM　必要証拠金がAccountFreeMarginCheckでとれなかったため、推定" , __LINE__);
   
   if(ShowTestMsg == true) printf( "[%d]テストCOMM　指値=%s  桁数=%s  ロット=%s  レバレッジ=%s" , __LINE__,
            DoubleToStr(mClose) ,
            DoubleToStr(digits),
            DoubleToStr(mLotSize),
            DoubleToStr(mLev)
            );
   if(mLev == 0) {
      mRet = 0.0;
   }
   else {
      mRet = NormalizeDouble(mClose * mLotSize / mLev, global_Digits);
   if(ShowTestMsg == true) printf( "[%d]テストCOMMON　推定した証拠金=%s" , __LINE__, DoubleToStr(mRet, global_Digits));
      
   }
   
   return mRet;
}


//+------------------------------------------------------------------+
//|https://autofx100.com
//|【関数】資産のＮ％のリスクのロット数を計算する                    |
//|                                                                  |
//|【引数】 IN OUT  引数名             説明                          |
//|        --------------------------------------------------------- |
//|         ○      mFunds             資金                          |
//|                                      AccountFreeMargin()         |
//|                                      AccountBalance()            |
//|         ○      mSymbol            通貨ペア                      |
//|         ○      mStopLossPips      損切り値（pips）              |
//|         ○      mRiskPercent       リスク率（％）                |
//|                                                                  |
//|【戻値】ロット数                                                  |
//|                                                                  |
//|【備考】計算した結果、最小ロット数未満になる場合、-1を返す        |
//+------------------------------------------------------------------+
double calcLotSizeRiskPercent(double mFunds, string mSymbol, double mStopLossPips, double mRiskPercent)
{
// 取引対象の通貨を1ロット売買した時の1ポイント（pipsではない！）当たりの変動額
double tickValue = MarketInfo(mSymbol, MODE_TICKVALUE);

// tickValueは最小価格単位で計算されるため、3/5桁業者の場合、10倍しないと1pipsにならない
double mDigits = MarketInfo(mSymbol, MODE_DIGITS);
if(mDigits == 3.0 || mDigits == 5.0){
   tickValue *= 10.0;
}

double riskAmount = mFunds * (mRiskPercent / 100.0);

double lotSize = riskAmount / (mStopLossPips * tickValue);

double lotStep = MarketInfo(mSymbol, MODE_LOTSTEP);

// ロットステップ単位未満は切り捨て
// 0.123⇒0.12（lotStep=0.01の場合）
// 0.123⇒0.1 （lotStep=0.1の場合）
lotSize = MathFloor(lotSize / lotStep) * lotStep;

// 証拠金ベースの制限
double margin = MarketInfo(mSymbol, MODE_MARGINREQUIRED);
  
if(margin > 0.0){
   double accountMax = mFunds / margin;

   accountMax = MathFloor(accountMax / lotStep) * lotStep;

   if(lotSize > accountMax){
      lotSize = accountMax;
   }
}

// 最大ロット数、最小ロット数対応
double minLots = MarketInfo(mSymbol, MODE_MINLOT);
double maxLots = MarketInfo(mSymbol, MODE_MAXLOT);

if(lotSize < minLots) {
   // 仕掛けようとするロット数が最小単位に満たない場合、
   // そのまま仕掛けると過剰リスクになるため、エラーに
   lotSize = -1.0;
}
else if(lotSize >= maxLots){
    lotSize = maxLots;
}

return(lotSize);
}


// 指定したPIPS数の利益確定又は損切を行う。
bool do_ForcedSettlement(int magic, string mSymbol , double mTP, double mSL) {
   int i;
   bool ret = true;
   
// mTPとmSLともに負であっても、commentを使った決済ができるケースがあるため、以下を削除
//   if(mTP < 0.0 && mSL < 0.0) {
//      return false;
  

   for(i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
         if(OrderMagicNumber() == magic) {
            if( (StringLen(mSymbol) > 0 && StringCompare(OrderSymbol(), mSymbol) == 0) ) {
               double mOpen = OrderOpenPrice();
               int mBuySell = OrderType();
               string mComment = OrderComment();
               double mMarketinfoMODE_BID = MarketInfo(mSymbol,MODE_BID);     
               double mMarketinfoMODE_ASK = MarketInfo(mSymbol,MODE_ASK);
                                                   
               double local_TPPrice = 0.0;
               double local_SLPrice = 0.0;         
               bool flagComment = get_TPSL_FromComment(mComment, local_TPPrice, local_SLPrice);
//printf( "[%d]COMM コメントから取得したTP>%s<   SL>%s<" , __LINE__ , DoubleToString(local_TPPrice, 5), DoubleToString(local_SLPrice, 5));               
               // 引数3, 4が共に負で、commentから決済用の値も取得できない場合は、次の取引に処理を移す。
               if(mTP < 0.0 && mSL < 0.0 && flagComment == false) {
                  continue;
               }   
               
               // 利確、損切が両方ともセットされているときは、強制決済の対象外とする。
               if(OrderStopLoss() > 0.0 && OrderTakeProfit() > 0.0) {
                  continue;
               }

               // 
               //
               // 取引が持つcommentを使った決済
               //
               if(StringLen(mComment) > 0) {
   
                  if(mBuySell == OP_BUY) {
                     if(mMarketinfoMODE_BID > 0.0 && local_TPPrice > 0.0 && local_SLPrice > 0.0) {
                        // 実行時点のBIDが利確値を超えるか、損切値を下回っていれば、決済する。
                        if(mMarketinfoMODE_BID >= local_TPPrice || mMarketinfoMODE_BID <= local_SLPrice) {
                           if(!OrderClose(OrderTicket(),OrderLots(),mMarketinfoMODE_BID,SLIPPAGE,LINE_COLOR_CLOSE)) {
                              printf( "[%d]COMMエラー 決済の失敗:：%s" , __LINE__ , GetLastError());
                           }  
                           else {
   /*                           printf( "[%d]COMM ロングの強制決済実施　チケット=%d 利確設定値=>%s< 損切設定値=>%s< コメントのTP=>%s< SL=>%s< 判定に使うBID=>%s<" , __LINE__ , 
                                      OrderTicket(),
                                      DoubleToStr(OrderTakeProfit(), 5),
                                      DoubleToStr(OrderStopLoss(), 5),
                                      DoubleToStr(local_TPPrice, 5),
                                      DoubleToStr(local_SLPrice, 5),
                                      DoubleToStr(mMarketinfoMODE_BID, 5)
                              );*/
                           }                  
                           // 決済に失敗しても同じ取引の決済を試みず、以降の処理をジャンプする。
                           continue;
                        }
                     }
                  }
                  else if(mBuySell == OP_SELL) {
                     if(mMarketinfoMODE_ASK > 0.0 && local_TPPrice > 0.0 && local_SLPrice > 0.0) {
                        // 実行時点のASKが利確値を下回るか、損切値を上回っていれば、決済する。
                        if(mMarketinfoMODE_ASK >= local_SLPrice || mMarketinfoMODE_ASK <= local_TPPrice) {
                           if(!OrderClose(OrderTicket(),OrderLots(),mMarketinfoMODE_ASK,SLIPPAGE,LINE_COLOR_CLOSE)) {
                              printf( "[%d]COMMエラー 決済の失敗:：%s" , __LINE__ , GetLastError());
                           }  
                           else {
/*                              printf( "[%d]COMM ショートの強制決済実施　チケット=%d 　利確設定値=>%s< 損切設定値=>%s< コメントのTP=>%s< SL=>%s< 判定に使うBID=>%s<" , __LINE__ , 
                                      OrderTicket(),
                                      DoubleToStr(OrderTakeProfit(), 5),
                                      DoubleToStr(OrderStopLoss(), 5),
                                      DoubleToStr(local_TPPrice, 5),
                                      DoubleToStr(local_SLPrice, 5),
                                      DoubleToStr(mMarketinfoMODE_ASK, 5)
                              );*/
                           }                                   
                           // 決済に失敗しても同じ取引の決済を試みず、以降の処理をジャンプする。
                           continue;
                        }
                     }               
                  }
               }

               // 
               // 第3, 4引数を使った決済
               //
               // 第3, 4引数が共に負の場合は、以降の処理をジャンプする。
               if(mTP < 0.0 && mSL < 0.0) {
                  continue;
               }  
               // ロングの場合の利確、損切
               if(mBuySell == OP_BUY) {
       
                  // 利確
                  if( (mTP > 0 && NormalizeDouble(mMarketinfoMODE_BID, global_Digits) > NormalizeDouble(mOpen, global_Digits) && (NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mOpen, global_Digits)) > NormalizeDouble(change_PiPS2Point(mTP), global_Digits)) 
                       ||
                      (mTP == 0 && (NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mOpen, global_Digits)) == 0.0)
                    ) {
                     if(!OrderClose(OrderTicket(),OrderLots(),mMarketinfoMODE_BID,SLIPPAGE,LINE_COLOR_CLOSE)) {
                        printf( "[%d]COMMエラー 決済の失敗:：%s" , __LINE__ , GetLastError());
                        ret = false;
                     }
                     else {
                        printf( "[%d]COMM ロングの強制決済実施　　チケット=%d 利確設定値=>%s< 損切設定値=>%s< コメントのTP=>%s< SL=>%s< 判定に使うBID=>%s<" , __LINE__ , 
                                OrderTicket(),
                                DoubleToStr(OrderTakeProfit(), 5),
                                DoubleToStr(OrderStopLoss(), 5),
                                DoubleToStr(local_TPPrice, 5),
                                DoubleToStr(local_SLPrice, 5),
                                DoubleToStr(mMarketinfoMODE_BID, 5)
                        );
                     }                  
                               
                  }
                  // 損切
                  if( (mSL > 0 && NormalizeDouble(mMarketinfoMODE_BID, global_Digits) < NormalizeDouble(mOpen, global_Digits) && (NormalizeDouble(mOpen, global_Digits) - NormalizeDouble(mMarketinfoMODE_BID, global_Digits)) > NormalizeDouble(change_PiPS2Point(mSL), global_Digits)) 
                       || 
                      (mSL == 0 && (NormalizeDouble(mOpen, global_Digits) - NormalizeDouble(mMarketinfoMODE_BID, global_Digits)) == 0.0)
                    ) {
                     if(!OrderClose(OrderTicket(),OrderLots(),mMarketinfoMODE_BID,SLIPPAGE,LINE_COLOR_CLOSE)) {
                        printf( "[%d]COMMエラー 決済の失敗:：%s" , __LINE__ , GetLastError());
                        ret = false;
                     }
                     else {
                        printf( "[%d]COMM ロングの強制決済実施　　チケット=%d 利確設定値=>%s< 損切設定値=>%s< コメントのTP=>%s< SL=>%s< 判定に使うBID=>%s<" , __LINE__ , 
                                OrderTicket(),
                                DoubleToStr(OrderTakeProfit(), 5),
                                DoubleToStr(OrderStopLoss(), 5),
                                DoubleToStr(local_TPPrice, 5),
                                DoubleToStr(local_SLPrice, 5),
                                DoubleToStr(mMarketinfoMODE_BID, 5)
                        );
                     }                  
                  }
               }
               
               //　ショートの場合の利確、損切
               else if(mBuySell == OP_SELL) {
                  // 利確
                  if( (mTP > 0 && NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) < NormalizeDouble(mOpen, global_Digits) && (NormalizeDouble(mOpen, global_Digits) - NormalizeDouble(mMarketinfoMODE_ASK, global_Digits))  > NormalizeDouble(change_PiPS2Point(mTP), global_Digits)) 
                       ||
                      (mTP == 0 && (NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) - NormalizeDouble(mOpen, global_Digits)) == 0.0)
                    ) {
                     if(!OrderClose(OrderTicket(),OrderLots(),mMarketinfoMODE_ASK,SLIPPAGE,LINE_COLOR_CLOSE)) {
                        printf( "[%d]COMMエラー 決済の失敗:：%s" , __LINE__ , GetLastError());
                        ret = false;
                     }
                     else {
                        printf( "[%d]COMM ショートの強制決済実施　　チケット=%d 利確設定値=>%s< 損切設定値=>%s< コメントのTP=>%s< SL=>%s< 判定に使うBID=>%s<" , __LINE__ , 
                                OrderTicket(),
                                DoubleToStr(OrderTakeProfit(), 5),
                                DoubleToStr(OrderStopLoss(), 5),
                                DoubleToStr(local_TPPrice, 5),
                                DoubleToStr(local_SLPrice, 5),
                                DoubleToStr(mMarketinfoMODE_ASK, 5)
                        );
                     }                                   
                     
                     
                  }
                  // 損切
                  else if( (mSL > 0 && NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) > NormalizeDouble(mOpen, global_Digits) && (NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) - NormalizeDouble(mOpen, global_Digits)) > NormalizeDouble(change_PiPS2Point(mSL), global_Digits)) 
                            || 
                           (mSL == 0 && (NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) - NormalizeDouble(mOpen, global_Digits)) == 0.0)
                          ){
                     if(!OrderClose(OrderTicket(),OrderLots(),mMarketinfoMODE_ASK,SLIPPAGE,LINE_COLOR_CLOSE)) {
                        printf( "[%d]COMMエラー 決済の失敗:：%s" , __LINE__ , GetLastError());
                        ret = false;
                     }
                     else {
                        printf( "[%d]COMM ショートの強制決済実施　　チケット=%d 利確設定値=>%s< 損切設定値=>%s< コメントのTP=>%s< SL=>%s< 判定に使うBID=>%s<" , __LINE__ , 
                                OrderTicket(),
                                DoubleToStr(OrderTakeProfit(), 5),
                                DoubleToStr(OrderStopLoss(), 5),
                                DoubleToStr(local_TPPrice, 5),
                                DoubleToStr(local_SLPrice, 5),
                                DoubleToStr(mMarketinfoMODE_ASK, 5)
                        );
                     }                                   
                                
                  }            
               }
            }
         }
      }
   }
   return ret;
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
bool calcRegressionLine(double &data[], int dataNum, double &slope, double &intercept) {
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
      mean_x = mean_x + i;
      mean_y = mean_y + data[i];
//printf("[%d]COMM data[%d]=%s--xの合計=%s　yの合計=%s", __LINE__,
//            i,DoubleToStr(data[i], global_Digits), DoubleToStr(mean_x, global_Digits), DoubleToStr(mean_y, global_Digits));
      
      
   }
   mean_x = mean_x / dataNum;  // xの平均。
   mean_y = mean_y / dataNum;  // yの平均
/*printf("[%d]COMM dataNum=%d xの平均=%s　yの平均=%s", __LINE__,
        dataNum,
        DoubleToStr(mean_x, global_Digits),
        DoubleToStr(mean_y, global_Digits)
        );*/
   
   // 傾きの計算
   double sumXY = 0.0;
   double sumX2 = 0.0;
   for(i = 0; i < dataNum; i++) {
      sumXY = sumXY + (i - mean_x)*(data[i] - mean_y);
      sumX2 = sumX2 + (i - mean_x)*(i - mean_x);
   }
   if(sumX2 <= 0.0) {
      return false;
   }
   else {
      slope = sumXY / sumX2;
   }
   
   //　切片の計算
   intercept = mean_y - slope * mean_x;
   
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

//printf( "[%d]COMM　重回帰 xの平均=%s  yの平均=%s" , __LINE__, DoubleToStr(mean_x, global_Digits*2), DoubleToStr(mean_y, global_Digits*2)); 
//printf( "[%d]COMM　重回帰 yの平均=%s　　　元ネタ　%s    %s" , __LINE__, DoubleToStr(mean_y, global_Digits*2), DoubleToStr(data_y[1], global_Digits*2), DoubleToStr(data_y[2], global_Digits*2)); 
  
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



//+------------------------------------------------------------------+
//| RCI(Rank Correlation Index)を算出する[配列ベース]
//+------------------------------------------------------------------+
// 構造体型宣言
struct struct_rci_data {                         // RCI算出用構造体
   datetime date_value;                        // 日付
   double   rate_value;                         // 価格
   int      rank_date;                          // 日付順位
   int      rank_rate;                          // 価格順位
   double   rank_adjust_rate;                  // 価格順位(調整後)
};

double mRCI3(int     in_timeframe,       // タイムフレーム
             int     in_time_period ,    // 算出期間
             int     in_index            // インデックス
             ) {
// 【参考文献】https://yukifx.web.fc2.com/sub/make/01_root/cone/mql4begin_indsub_rci3.html             
   double ret = 0;   // 戻り値
   
   double in_array[];
   ArrayResize(in_array, 100);

   double buf;
   for(int i = 0; i < in_time_period; i++) {
      buf = iClose(global_Symbol, in_timeframe, in_index + i);
//printf("[%d]COMM　buf=%s", __LINE__, DoubleToStr(buf));
      
      in_array[i] = buf;

//printf("[%d]COMM　global_Symbol=%s  in_timeframe=%d in_index+i=%d", __LINE__, global_Symbol, in_timeframe, in_index + i);
//printf("[%d]COMM　iClose(global_Symbol, in_timeframe, in_index + i)=%s>>>%s", __LINE__, DoubleToStr(iClose(global_Symbol, in_timeframe, in_index + i)),DoubleToStr(in_array[i]));


      
   }

       
   int    array_count = ArraySize(in_array);       // 配列要素数取得
//   int    array_count = in_time_period;       // 配列要素数取得
   int    end_index = in_index + in_time_period;    // ループエンド

   if ( end_index < array_count ) {                  // 配列範囲内チェック
      struct_rci_data  temp_st_rci[];                       // RCI算出用構造体動的配列
      int arrayst_count = ArrayResize(                    // 動的配列サイズ変更
                                      temp_st_rci ,      // 変更する配列
                                      in_time_period ,   // 新しい配列サイズ
                                      0                  // 予備サイズ
                                      );
//printf("[%d]COMM　arrayst_count=%d", __LINE__, arrayst_count);

        // データ設定
      int temp_rank = 1;
      int arr_count = 0;
      for ( int icount = in_index ; icount < end_index ; icount++  ) {
         temp_st_rci[arr_count].date_value = Time[icount];        // 日付データ設定
         temp_st_rci[arr_count].rate_value = in_array[icount];    // 価格データ設定
         temp_st_rci[arr_count].rank_date  = temp_rank;           // 日付順位(ランク)設定
         temp_rank++;
         arr_count++;
      }

      int main_count = 0;
      int sub_count = 0;
      // 価格順ソート
      for (main_count = 0; main_count < arrayst_count - 1 ; main_count++ ) {
         for (sub_count = main_count + 1; sub_count < arrayst_count ; sub_count++ ) {
            // 次の配列メンバと比較して小さい場合
            if ( temp_st_rci[main_count].rate_value < temp_st_rci[sub_count].rate_value ) {
               // 構造体配列を入れ替える
               struct_rci_data temp_swap  = temp_st_rci[main_count];      // 比較元のデータ退避
               temp_st_rci[main_count]    = temp_st_rci[sub_count];       // 比較元のデータ入れ替え
               temp_st_rci[sub_count]     = temp_swap;                    // 比較先に退避データをセット
            }
         }
      }
      // 価格RANK設定
      for(main_count = 0; main_count < arrayst_count ; main_count++ ) {
         int temp_set_rank = main_count + 1;
         temp_st_rci[main_count].rank_rate = temp_set_rank;
         temp_st_rci[main_count].rank_adjust_rate = (double)temp_set_rank;
      }

      // 価格RANKの同値調整
      for (main_count = 0 ; main_count < arrayst_count - 1 ; main_count++ ) {
         double sum_rank   = (double)temp_st_rci[main_count].rank_rate;     // ランクサマリー
         int    same_count = 0;                                              // 同値検出カウント
         for (sub_count = main_count + 1 ; sub_count < arrayst_count ; sub_count++ ) {
            if ( temp_st_rci[main_count].rate_value == temp_st_rci[sub_count].rate_value ) { // 同値の場合
               sum_rank += (double)temp_st_rci[sub_count].rank_rate;       // ランクサマリーにランクを加算
               same_count++;                                                // 同値検出カウントをインクリメント
            } 
            else {                                                        // 同値以外の場合
               break;                                                      // 同値の場合forループから抜ける
            }
         }

         if ( same_count >= 1 ) {                                             // 同値価格が1つ以上ある場合
            double set_adjust_rank = sum_rank / ((double)same_count + 1);   // ランクの中間値を算出
            for( int ad_count = 0 ; ad_count <= same_count; ad_count++ ) {  // 同値検出カウント分ループ
               // 価格順位(調整後)に中間値を設定
               temp_st_rci[ad_count + main_count].rank_adjust_rate = set_adjust_rank; 
            }

            main_count += same_count;                         // メインループを同値検出カウント分スキップさせる

         }
      }

      // RCIのd算出
      double sum_d = 0;
      double temp_diff = 0;
      for(main_count = 0; main_count < arrayst_count ; main_count++ ) {
         temp_diff = (double)temp_st_rci[main_count].rank_date - temp_st_rci[main_count].rank_adjust_rate;
         sum_d += MathPow( temp_diff , 2 );
      }

      // RCIのn(n^2 - 1)算出
      int temp_div = in_time_period * ( (int)MathPow( in_time_period , 2 ) - 1 );

      // RCIを算出
      if ( temp_div > 0) {            // 0除算対策
         ret = 100 * ( 1 - ( 6 * sum_d / (double)temp_div ) );
      }
   }

   return ret;       // 戻り値を返す
}


double RCIExtMapBuffer1[100];
double RCIR2[100];
bool   RCIdirection = true; 

// https://qiita.com/bucchi49/items/a08f240b920fc5f90a87
double mRCI2(const string symbol, int timeframe, int period, int index)
{   
    int rank;
    double d = 0;
    double close_arr[];
    ArrayResize(close_arr, period); 

    for (int i = 0; i < period; i++) {
        close_arr[i] = iClose(symbol, timeframe, index + i);
//printf( "[%d]COMM　%d--RCI＝%s", __LINE__, i, DoubleToStr(close_arr[i]));        
    }

    ArraySort(close_arr, WHOLE_ARRAY, 0, MODE_DESCEND);

    for (int j = 0; j < period; j++) {
        rank = ArrayBsearch(close_arr,
                            iClose(symbol, timeframe, index + j),
                            WHOLE_ARRAY,
                            0,
                            MODE_DESCEND);
        d += MathPow(j - rank, 2);
    }
//printf( "[%d]COMM　d＝%s", __LINE__, i, DoubleToStr(d));        
    

    return((1 - 6 * d / (period * (period * period - 1))) * 100);
}

double mRCI(int rangeN, int mNum)
  {
   if(rangeN > 52) return -1;
   if(mNum < 0)          return -1;

   double PriceInt[100];
   int i, k, limit;
   double RCImultiply;
//20170610   limit = 10; 
   limit = mNum; 
   RCImultiply = MathPow(10, Digits);
   for(i = limit; i >= 0; i--)
     {
       for(k = 0; k < rangeN; k++) {
           PriceInt[k] = NormalizeDouble(Close[i+k], global_Digits) * NormalizeDouble(RCImultiply, global_Digits);
       }

       RankPrices(rangeN, PriceInt);
       RCIExtMapBuffer1[i] = SpearmanRankCorrelation(RCIR2,rangeN);
     }
//----
   return RCIExtMapBuffer1[mNum];
  }
  
  
//+------------------------------------------------------------------+
//| スピアマン関数 (RCI計算用関数)      　　                      |
//+------------------------------------------------------------------+
double SpearmanRankCorrelation(double &Ranks[], int N)
  {
//----
   double res = 0.0;
   double z2  = 0.0;
   int i;
   for(i = 0; i < N; i++)
     {
//       z2 += MathPow(Ranks[i] - i - 1, 2);
       z2 += (Ranks[i] - i - 1) * (Ranks[i] - i - 1);
     }
//   res = 1 - 6*z2 / (MathPow(N,3) - N);
   res = 1 - 6*z2 / (N*N*N - N);
//----
   return(res);
  }
//+------------------------------------------------------------------+
//| 価格の順位関数(RCI計算用関数)                           |
//+------------------------------------------------------------------+
void RankPrices(int rangeN, double &InitialArray[])  {
//----
   double    SortInt[100];
   int i, k, m, counter;
   double dublicat = 0.0;
   double etalon = 0.0;
   double dcounter, averageRank;
   double TrueRanks[];
   ArrayResize(TrueRanks, rangeN);
   ArrayCopy(SortInt, InitialArray);
   for(i = 0; i < rangeN; i++) 
       TrueRanks[i] = i + 1;
   if(RCIdirection)
       ArraySort(SortInt, 0, 0, MODE_DESCEND);
   else
       ArraySort(SortInt, 0, 0, MODE_ASCEND);
   for(i = 0; i < rangeN-1; i++)
     {
       if(NormalizeDouble(SortInt[i], global_Digits) != NormalizeDouble(SortInt[i+1], global_Digits)) 
           continue;
       dublicat = SortInt[i];
       k = i + 1;
       counter = 1;
       averageRank = i + 1;
       while(k < rangeN)
         {
           if(NormalizeDouble(SortInt[k], global_Digits) == NormalizeDouble(dublicat, global_Digits))
             {
               counter++;
               averageRank += k + 1;
               k++;
             }
           else
               break;
         }
       dcounter = counter;
       averageRank = averageRank / dcounter;
       for(m = i; m < k; m++)
           TrueRanks[m] = averageRank;
       i = k;
     }
   for(i = 0; i < rangeN; i++)
     {
       etalon = InitialArray[i];
       k = 0;
       while(k < rangeN)
         {
           if(etalon == SortInt[k])
             {
               RCIR2[i] = TrueRanks[k];
               break;
             }
           k++;
         }
     }
//----
   return;
  }


// 引数startShift以前の直近の移動平均のゴールデンクロスとデッドクロスを探す。
// 発見したゴールデンクロス発生時点のシフトとデッドクロス発生時点のシフトを引数lastGCとlastDCに代入する。
// 計算中に不具合が発生すれば、falseを返す。その際、引数lastGCとlastDCは-1。それ以外は、trueを返す。
// https://gplustuts.com/ea-goldencross/
// 多くのトレーダーが使用しているのは、5,25,75 という3種類です。→25MAと75MAを使う。
bool getLastMA_Cross(int mTimeFrame, // 入力：移動平均を計算するための時間軸
                     int mStartShift, // 入力：計算開始位置
                     int &lastGC,    // 出力：直近のゴールデンクロスが発生したシフト
                     int &lastDC     // 出力：直近のデッドクロスが発生したシフト
                     ){
   int max_shift = 500;  // max_shiftのシフト数だけ、GC, DCを探す。見つからなかったら、-1をセットする。
   int maLongSpan = 25;
   int msShortSpan = 5;
   if(mStartShift < 0) {
      lastGC = INT_VALUE_MIN;
      lastDC = INT_VALUE_MIN;
      return false;
   }
   
   int i = 0;
   lastGC = INT_VALUE_MIN;
   lastDC = INT_VALUE_MIN;
   double maLong_1 = 0.0;  // 長期足のより最近の(シフト数が小さい）移動平均値
   double maLong_2 = 0.0;  // 長期足のより過去の(シフト数が大きい）移動平均値
   double maShort_1 = 0.0; // 短期足のより最近の(シフト数が小さい）移動平均値
   double maShort_2 = 0.0; // 短期足のより過去の(シフト数が大きい）移動平均値
   
   for(i = mStartShift; i < mStartShift + max_shift;i++) {
      // ゴールデンクロスが見つかっていなければ、ゴールデンクロスが発生したかを判定する
      if(lastGC < 0) {
         // まず、注目しているシフトの長期足MA　< 短期足MAが成立すること。
         maLong_1 = iMA(
                       global_Symbol,// 通貨ペア
                       mTimeFrame,   // 時間軸
                       maLongSpan,   // MAの平均期間
                       0,            // MAシフト
                       MODE_SMA,     // MAの平均化メソッド
                       PRICE_CLOSE,  // 適用価格
                       i             // シフト
                      );
         maShort_1 = iMA(
                       global_Symbol,// 通貨ペア
                       mTimeFrame,   // 時間軸
                       msShortSpan,  // MAの平均期間
                       0,            // MAシフト
                       MODE_SMA,     // MAの平均化メソッド
                       PRICE_CLOSE,  // 適用価格
                       i             // シフト
                      );        
         if(NormalizeDouble(maLong_1, global_Digits) < NormalizeDouble(maShort_1, global_Digits) ) {
            // さらに、注目しているシフトの１つ過去で長期足MA　> 短期足MAが成立すること。
            maLong_2 = iMA(
                          global_Symbol,// 通貨ペア
                          mTimeFrame,   // 時間軸
                          maLongSpan,   // MAの平均期間
                          0,            // MAシフト
                          MODE_SMA,     // MAの平均化メソッド
                          PRICE_CLOSE,  // 適用価格
                          i+1           // シフト
                         );
            maShort_2 = iMA(
                          global_Symbol,// 通貨ペア
                          mTimeFrame,   // 時間軸
                          msShortSpan,  // MAの平均期間
                          0,            // MAシフト
                          MODE_SMA,     // MAの平均化メソッド
                          PRICE_CLOSE,  // 適用価格
                          i+1           // シフト
                         );  
           
                          
            if(NormalizeDouble(maLong_2, global_Digits) > NormalizeDouble(maShort_2, global_Digits) ) {
           
               lastGC = i - mStartShift;
            }
         }
      } // ゴールデンクロス探索は、ここまで。
      // デッドクロスが見つかっていなければ、デッドクロスが発生したかを判定する。
      if(lastDC < 0) {
         // まず、注目しているシフトの長期足MA　> 短期足MAが成立すること。
         maLong_1 = iMA(
                       global_Symbol,// 通貨ペア
                       mTimeFrame,   // 時間軸
                       maLongSpan,   // MAの平均期間
                       0,            // MAシフト
                       MODE_SMA,     // MAの平均化メソッド
                       PRICE_CLOSE,  // 適用価格
                       i             // シフト
                      );
         maShort_1 = iMA(
                       global_Symbol,// 通貨ペア
                       mTimeFrame,   // 時間軸
                       msShortSpan,  // MAの平均期間
                       0,            // MAシフト
                       MODE_SMA,     // MAの平均化メソッド
                       PRICE_CLOSE,  // 適用価格
                       i             // シフト
                      );
         if(NormalizeDouble(maLong_1, global_Digits)  > NormalizeDouble(maShort_1, global_Digits) ) {
            // さらに、注目しているシフトの１つ過去で長期足MA　< 短期足MAが成立すること。
            maLong_2 = iMA(
                          global_Symbol,// 通貨ペア
                          mTimeFrame,   // 時間軸
                          maLongSpan,   // MAの平均期間
                          0,            // MAシフト
                          MODE_SMA,     // MAの平均化メソッド
                          PRICE_CLOSE,  // 適用価格
                          i+1           // シフト
                         );
            maShort_2 = iMA(
                          global_Symbol,// 通貨ペア
                          mTimeFrame,   // 時間軸
                          msShortSpan,  // MAの平均期間
                          0,            // MAシフト
                          MODE_SMA,     // MAの平均化メソッド
                          PRICE_CLOSE,  // 適用価格
                          i+1           // シフト
                         );   
            if(NormalizeDouble(maLong_2, global_Digits)  < NormalizeDouble(maShort_2, global_Digits) ) {
// printf( "[%dCOMM MAデッドクロス発生%s" , __LINE__ , TimeToStr(iTime(global_Symbol,0,i),TIME_DATE | TIME_MINUTES));
            
               lastDC = i - mStartShift;
            }
         }
      } // デッドクロス探索は、ここまで。
      
      if(lastGC >= 0 && lastDC >= 0) {
         //　ゴールデンクロスとデッドクロス両方見つかったので、処理を中断
         break;
      }
   } // for(i = startShift; i < startShift + max_shift;i++)
   
   return true;
}



// 引数startShift以前の直近のMACDのゴールデンクロスとデッドクロスを探す。
// 発見したゴールデンクロス発生時点のシフトとデッドクロス発生時点のシフトを引数lastGCとlastDCに代入する。
// 計算中に不具合が発生すれば、falseを返す。その際、引数lastGCとlastDCは-1。それ以外は、trueを返す。
// https://gplustuts.com/ea-goldencross/
// 多くのトレーダーが使用しているのは、5,25,75 という3種類です。→25MAと75MAを使う。
bool getLastMACD_Cross(int mTimeFrame,  // 入力：移動平均を計算するための時間軸
                       int mStartShift, // 入力：計算開始位置
                       int &lastGC,    // 出力：直近のゴールデンクロスが発生したシフト
                       int &lastDC     // 出力：直近のデッドクロスが発生したシフト
                     ){
   int max_shift = 500;  // max_shiftのシフト数だけ、GC, DCを探す。見つからなかったら、falseを返す。
   int maLongSpan = 75;
   int msShortSpan = 25;
   if(mStartShift < 0) {
      lastGC = INT_VALUE_MIN;
      lastDC = INT_VALUE_MIN;
      return false;
   }
   
   int i = 0;
   lastGC = INT_VALUE_MIN;
   lastDC = INT_VALUE_MIN;
   // MACDラインがシグナルラインを下から上に突き抜けたとき（交差したとき）を、ゴールデンクロス
   // MACDラインがシグナルラインを上から下に突き抜けたとき（交差したとき）を、デッドクロス

   double maMACD_1 = 0.0;   // MACDのより最近の(シフト数が小さい）値
   double maMACD_2 = 0.0;   // MACDのより過去の(シフト数が大きい）値
   double maSignal_1 = 0.0; // Signalのより最近の(シフト数が小さい）値
   double maSignal_2 = 0.0; // Signalのより過去の(シフト数が大きい）値
   
   for(i = mStartShift; i < mStartShift + max_shift;i++) {
//printf( "[%dCOMM MACDクロス検証時間　シフト=%d  %s" , __LINE__ , i, TimeToStr(iTime(global_Symbol,0,i),TIME_DATE | TIME_MINUTES));
   
      // ゴールデンクロスが見つかっていなければ、ゴールデンクロスかどうかを反省する
      if(lastGC < 0) {
         // まず、注目しているシフトのシグナル　< MACDが成立すること。
         maMACD_1 = iMACD(
                          global_Symbol,// 通貨ペア
                          mTimeFrame,   // 時間軸
                          12,           // ファーストEMA期間
                          26,           // スローEMA期間
                          9,            // シグナルライン期間
                          PRICE_CLOSE,  // 適用価格
                          MODE_MAIN,    // ラインインデックス
                          i             // シフト
                          ); 
         maSignal_1 = iMACD(
                          global_Symbol,// 通貨ペア
                          mTimeFrame,   // 時間軸
                          12,           // ファーストEMA期間
                          26,           // スローEMA期間
                          9,            // シグナルライン期間
                          PRICE_CLOSE,  // 適用価格
                          MODE_SIGNAL,  // ラインインデックス
                          i             // シフト
                          ); 
         if(NormalizeDouble(maSignal_1, global_Digits*2) < NormalizeDouble(maMACD_1, global_Digits*2)) { 
            // さらに、注目しているシフトの１つ過去でシグナル　>  MACDが成立すること。
            maMACD_2 = iMACD(
                          global_Symbol,// 通貨ペア
                          mTimeFrame,   // 時間軸
                          12,           // ファーストEMA期間
                          26,           // スローEMA期間
                          9,            // シグナルライン期間
                          PRICE_CLOSE,  // 適用価格
                          MODE_MAIN,    // ラインインデックス
                          i + 1         // シフト
                          ); 
            maSignal_2 = iMACD(
                          global_Symbol,// 通貨ペア
                          mTimeFrame,   // 時間軸
                          12,           // ファーストEMA期間
                          26,           // スローEMA期間
                          9,            // シグナルライン期間
                          PRICE_CLOSE,  // 適用価格
                          MODE_SIGNAL,  // ラインインデックス
                          i + 1         // シフト
                          ); 
            if(NormalizeDouble(maSignal_2, global_Digits) > NormalizeDouble(maMACD_2, global_Digits) ) {
                 // 直前のクロスまでの距離のため、startShiftを引く
                 lastGC = i - mStartShift;
            }
         }
      } // ゴールデンクロス探索は、ここまで。
      // デッドクロスが見つかっていなければ、ゴールデンクロスかどうかを反省する
      if(lastDC < 0) {
         // まず、注目しているシフトのシグナル　> MACDが成立すること。
         maMACD_1 = iMACD(
                          global_Symbol,// 通貨ペア
                          mTimeFrame,   // 時間軸
                          12,           // ファーストEMA期間
                          26,           // スローEMA期間
                          9,            // シグナルライン期間
                          PRICE_CLOSE,  // 適用価格
                          MODE_MAIN,    // ラインインデックス
                          i             // シフト
                          ); 
         maSignal_1 = iMACD(
                          global_Symbol,// 通貨ペア
                          mTimeFrame,   // 時間軸
                          12,           // ファーストEMA期間
                          26,           // スローEMA期間
                          9,            // シグナルライン期間
                          PRICE_CLOSE,  // 適用価格
                          MODE_SIGNAL,  // ラインインデックス
                          i             // シフト
                          ); 
         if(NormalizeDouble(maSignal_1, global_Digits) > NormalizeDouble(maMACD_1, global_Digits) ) {
            // さらに、注目しているシフトの１つ過去でシグナル　<  MACDが成立すること。
            maMACD_2 = iMACD(
                          global_Symbol,// 通貨ペア
                          mTimeFrame,   // 時間軸
                          12,           // ファーストEMA期間
                          26,           // スローEMA期間
                          9,            // シグナルライン期間
                          PRICE_CLOSE,  // 適用価格
                          MODE_MAIN,    // ラインインデックス
                          i + 1         // シフト
                          ); 
            maSignal_2 = iMACD(
                          global_Symbol,// 通貨ペア
                          mTimeFrame,   // 時間軸
                          12,           // ファーストEMA期間
                          26,           // スローEMA期間
                          9,            // シグナルライン期間
                          PRICE_CLOSE,  // 適用価格
                          MODE_SIGNAL,  // ラインインデックス
                          i + 1         // シフト
                          ); 
            if(NormalizeDouble(maSignal_2, global_Digits) < NormalizeDouble(maMACD_2, global_Digits)) {
              // 直前のクロスまでの距離のため、startShiftを引く
            
               lastDC = i - mStartShift;
            }
         }
      } // ゴールデンクロス探索は、ここまで。      
      if(lastGC >= 0 && lastDC >= 0) {
         //　ゴールデンクロスとデッドクロス両方見つかったので、処理を中断
         break;
      }
   } // for(i = startShift; i < startShift + max_shift;i++)
   
   return true;
}



// 引数startShift以前の直近のストキャスティクスのゴールデンクロスとデッドクロスを探す。
// 発見したゴールデンクロス発生時点のシフトとデッドクロス発生時点のシフトを引数lastGCとlastDCに代入する。
// 計算中に不具合が発生すれば、falseを返す。その際、引数lastGCとlastDCは-1。それ以外は、trueを返す。
// https://gplustuts.com/ea-goldencross/
// 多くのトレーダーが使用しているのは、5,25,75 という3種類です。→25MAと75MAを使う。
bool getLastSTOC_Cross(int mTimeFrame,  // 入力：移動平均を計算するための時間軸
                       int mStartShift, // 入力：計算開始位置
                       int &lastGC,    // 出力：直近のゴールデンクロスが発生したシフト
                       int &lastDC     // 出力：直近のデッドクロスが発生したシフト
                       ){
   int max_shift = 500;  // max_shiftのシフト数だけ、GC, DCを探す。見つからなかったら、-1をセットする。
   int maLongSpan = 75;
   int msShortSpan = 25;
   if(mStartShift < 0) {
      lastGC = INT_VALUE_MIN;
      lastDC = INT_VALUE_MIN;
      return false;
   }
   
   int i = 0;
   lastGC = INT_VALUE_MIN;
   lastDC = INT_VALUE_MIN;
   // ストキャスティクスがシグナルを下から上に突き抜けたとき（交差したとき）を、ゴールデンクロス
   // ストキャスティクスがシグナルを上から下に突き抜けたとき（交差したとき）を、デッドクロス

   double maSTOC_1 = 0.0;   // ストキャスティクスのより最近の(シフト数が小さい）値
   double maSTOC_2 = 0.0;   // ストキャスティクスのより過去の(シフト数が大きい）値
   double maSignal_1 = 0.0; // Signalのより最近の(シフト数が小さい）値
   double maSignal_2 = 0.0; // Signalのより過去の(シフト数が大きい）値
   
   for(i = mStartShift; i < mStartShift + max_shift;i++) {
      // ゴールデンクロスが見つかっていなければ、ゴールデンクロスかどうかを反省する
      if(lastGC < 0) {
         // まず、注目しているシフトのシグナル　< MACDが成立すること。
         maSTOC_1 = iStochastic(
                                global_Symbol,// 通貨ペア
                                mTimeFrame,   // 時間軸
                                5,            // %K期間
                                3,            // %D期間
                                3,            // スローイング
                                MODE_SMA,     // 平均化メソッド
                                0,            // 価格(Low/HighまたはClose/Close)
                                MODE_MAIN,    // ラインインデックス
                                i             // シフト
                                );

         maSignal_1 = iStochastic(
                                global_Symbol,// 通貨ペア
                                mTimeFrame,   // 時間軸
                                5,            // %K期間
                                3,            // %D期間
                                3,            // スローイング
                                MODE_SMA,     // 平均化メソッド
                                0,            // 価格(Low/HighまたはClose/Close)
                                MODE_SIGNAL,    // ラインインデックス
                                i             // シフト
                                );
         if(NormalizeDouble(maSignal_1, global_Digits) < NormalizeDouble(maSTOC_1, global_Digits)) {
            // さらに、注目しているシフトの１つ過去でシグナル　>  MACDが成立すること。
            maSTOC_2 = iStochastic(
                                global_Symbol,// 通貨ペア
                                mTimeFrame,   // 時間軸
                                5,            // %K期間
                                3,            // %D期間
                                3,            // スローイング
                                MODE_SMA,     // 平均化メソッド
                                0,            // 価格(Low/HighまたはClose/Close)
                                MODE_MAIN,    // ラインインデックス
                                i + 1         // シフト
                                );
            maSignal_2 =iStochastic(
                                global_Symbol,// 通貨ペア
                                mTimeFrame,   // 時間軸
                                5,            // %K期間
                                3,            // %D期間
                                3,            // スローイング
                                MODE_SMA,     // 平均化メソッド
                                0,            // 価格(Low/HighまたはClose/Close)
                                MODE_SIGNAL,  // ラインインデックス
                                i  + 1        // シフト
                                );
            if(NormalizeDouble(maSignal_2, global_Digits) > NormalizeDouble(maSTOC_2, global_Digits)) {
               lastGC = i - mStartShift;
            }
         }
      } // ゴールデンクロス探索は、ここまで。
      // デッドクロスが見つかっていなければ、ゴールデンクロスかどうかを反省する
      if(lastDC < 0) {
         // まず、注目しているシフトのシグナル　> MACDが成立すること。
         maSTOC_1 = iStochastic(
                                global_Symbol,// 通貨ペア
                                mTimeFrame,   // 時間軸
                                5,            // %K期間
                                3,            // %D期間
                                3,            // スローイング
                                MODE_SMA,     // 平均化メソッド
                                0,            // 価格(Low/HighまたはClose/Close)
                                MODE_MAIN,    // ラインインデックス
                                i             // シフト
                                );

         maSignal_1 = iStochastic(
                                global_Symbol,// 通貨ペア
                                mTimeFrame,   // 時間軸
                                5,            // %K期間
                                3,            // %D期間
                                3,            // スローイング
                                MODE_SMA,     // 平均化メソッド
                                0,            // 価格(Low/HighまたはClose/Close)
                                MODE_SIGNAL,    // ラインインデックス
                                i             // シフト
                                );
 
         if(NormalizeDouble(maSignal_1, global_Digits) > NormalizeDouble(maSTOC_1, global_Digits)) {
            // さらに、注目しているシフトの１つ過去でシグナル　<  MACDが成立すること。
            maSTOC_2 = iStochastic(
                                global_Symbol,// 通貨ペア
                                mTimeFrame,   // 時間軸
                                5,            // %K期間
                                3,            // %D期間
                                3,            // スローイング
                                MODE_SMA,     // 平均化メソッド
                                0,            // 価格(Low/HighまたはClose/Close)
                                MODE_MAIN,    // ラインインデックス
                                i + 1         // シフト
                                );
            maSignal_2 =iStochastic(
                                global_Symbol,// 通貨ペア
                                mTimeFrame,   // 時間軸
                                5,            // %K期間
                                3,            // %D期間
                                3,            // スローイング
                                MODE_SMA,     // 平均化メソッド
                                0,            // 価格(Low/HighまたはClose/Close)
                                MODE_SIGNAL,  // ラインインデックス
                                i  + 1        // シフト
                                );
            if(NormalizeDouble(maSignal_2, global_Digits) < NormalizeDouble(maSTOC_2, global_Digits)) {
               lastDC = i - mStartShift;
            }
         }
      } // ゴールデンクロス探索は、ここまで。      
      if(lastGC >= 0 && lastDC >= 0) {
         //　ゴールデンクロスとデッドクロス両方見つかったので、処理を中断
         break;
      }
   } // for(i = startShift; i < startShift + max_shift;i++)
   
   return true;
}



// 引数mCurrTFで渡した時間軸（0～9。ENUM_TIMEFRAMES型ではない)に対して、
// 引数mUpperLowerで渡しただけ上か下の時間軸（0～9。ENUM_TIMEFRAMES型ではない)を返す
// 【注意】
// ・引数も返り値も0(PERIOD_00_INT)～9(PERIOD_MN1_INT)であり、ENUM_TIMEFRAMES型ではない。
int get_UpperLowerPeriodFrom1To9(int mCurrTF1to9,    //　現在の時間軸。0,1(PERIOD_M1)～9(PERIOD_MN1)
                                 int mUpperLower // いくつ上下の時間軸を返すか。1つ上ならば+1、1つ下ならば-1
                                 ) {                                
   int retTF1to9 = -1; // 返り値
   if(mCurrTF1to9 == 0) {
      int buf = Period();
      // 引数にPERIOD_M1を渡せば1, PERIOD_M５を渡せば2,PERIOD_M15を渡せば3を返す。
      //　引数にPERIOD_MN1を渡した時に9を返すのが最大。
      mCurrTF1to9 = getTimeFrameReverse(buf);
   }
   retTF1to9 = mCurrTF1to9 + mUpperLower;
   if(retTF1to9 < 0) {
      return PERIOD_MINOVER_INT;
   }
   else if(retTF1to9 >= 0 && retTF1to9 <= 9) {
      return retTF1to9;
   }
   else if(retTF1to9 > 9) {
      return PERIOD_MAXOVER_INT;
   }
   else {
      return PERIOD_MINOVER_INT;
   }
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


void updateExternalParamCOMM() {
   //
   // TP_PIPSとSL_PIPSを通貨ペアに合わせて更新
   //
 //  TP_PIPS = change_PiPS2PointTP_PIPS);
 //  SL_PIPS = change_PiPS2PointSL_PIPS);

   //
   // 損切設定の更新
   //
   if(SL_PIPS_PER >= 0.0) {
      SL_PIPS = NormalizeDouble(TP_PIPS * SL_PIPS_PER / 100.0, global_Digits);
   } 

/*
   //
   // PING_WEIGHT_MINSの設定値が取りうる値かどうかをチェックの上、MQL4の定数に変換する。
   // 
   if(PING_WEIGHT_MINS < 0 || PING_WEIGHT_MINS > 9) {
      PING_WEIGHT_MINS = Period();
   }
   switch(PING_WEIGHT_MINS) {
      case 1:PING_WEIGHT_MINS = PERIOD_M1;
             break;
      case 2:PING_WEIGHT_MINS = PERIOD_M5;
             break;
      case 3:PING_WEIGHT_MINS = PERIOD_M15;
             break;
      case 4:PING_WEIGHT_MINS = PERIOD_M30;
             break;
      case 5:PING_WEIGHT_MINS = PERIOD_H1;
             break;
      case 6:PING_WEIGHT_MINS = PERIOD_H4;
             break;
      case 7:PING_WEIGHT_MINS = PERIOD_D1;
             break;
      case 8:PING_WEIGHT_MINS = PERIOD_W1;
             break;
      case 9:PING_WEIGHT_MINS = PERIOD_MN1;
             break;
      default:PING_WEIGHT_MINS = Period();
   } 
*/   

   //
   // TIME_FRAME_MAXMINの設定値が取りうる値かどうかをチェックの上、MQL4の定数に変換する。
   // 
   /*
   if(TIME_FRAME_MAXMIN < 0 || TIME_FRAME_MAXMIN > 9) {
      TIME_FRAME_MAXMIN = 0;
   }
   switch(TIME_FRAME_MAXMIN) {
      case 1:TIME_FRAME_MAXMIN = PERIOD_M1;
             break;
      case 2:TIME_FRAME_MAXMIN = PERIOD_M5;
             break;
      case 3:TIME_FRAME_MAXMIN = PERIOD_M15;
             break;
      case 4:TIME_FRAME_MAXMIN = PERIOD_M30;
             break;
      case 5:TIME_FRAME_MAXMIN = PERIOD_H1;
             break;
      case 6:TIME_FRAME_MAXMIN = PERIOD_H4;
             break;
      case 7:TIME_FRAME_MAXMIN = PERIOD_D1;
             break;
      case 8:TIME_FRAME_MAXMIN = PERIOD_W1;
             break;
      case 9:TIME_FRAME_MAXMIN = PERIOD_MN1;
             break;
      default:TIME_FRAME_MAXMIN = PERIOD_CURRENT;
   }   
*/
}

ENUM_TIMEFRAMES changeInt2ENUMTIMEFRAME(int mTimeFrame) {
   ENUM_TIMEFRAMES ret = PERIOD_CURRENT;
   if(mTimeFrame < 0 || mTimeFrame > 9) {
      ret = PERIOD_CURRENT;
   }
   switch(mTimeFrame) {
      case 1:ret = PERIOD_M1;
             break;
      case 2:ret = PERIOD_M5;
             break;
      case 3:ret = PERIOD_M15;
             break;
      case 4:ret = PERIOD_M30;
             break;
      case 5:ret = PERIOD_H1;
             break;
      case 6:ret = PERIOD_H4;
             break;
      case 7:ret = PERIOD_D1;
             break;
      case 8:ret = PERIOD_W1;
             break;
      case 9:ret = PERIOD_MN1;
             break;
      default:ret = PERIOD_CURRENT;
   }   
//printf( "[%d]COMMON mTimeFrame=>%d< を　ENUM=>%d<に変換" , __LINE__, mTimeFrame, ret);
   
   return ret;
}
//+-----------------------------------------------------------------------------------------------------------+
//|トレンドを分析し、上昇傾向ならばUpTrend、下降傾向ならばDownTrend、いずれとも判断できない場合はNoTrendを返す|
//+-----------------------------------------------------------------------------------------------------------+

// 1つ手前のシフトからEMAを取得して、EMAを結ぶ回帰直線の傾きでトレンドを分析する。
int get_Trend_EMA(int mTF) {  // 旧名称get_Trend_EMA
   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、NoTrendとする。
   if(mTF < PERIOD_CURRENT || mTF > PERIOD_MN1) {
      return NoTrend;
   }

   double EMA_1 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,0), global_Digits);
   double EMA_2 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,1), global_Digits);	
   double EMA_3 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,2), global_Digits);	
   double EMA_4 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,3), global_Digits);	
   double EMA_5 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,4), global_Digits);	
	
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
            TimeToStr(iTime(global_Symbol,mTF, 1)),DoubleToStr(data[2], global_Digits));*/

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

// mShift時点で、1つ手前のシフトからEMAからEMAを結ぶ回帰直線の傾きでトレンドを分析する。
// シフト追加版
int get_Trend_EMA(int mTF, int mShift) {  
//return get_Trend_EMA_PERIODH4(mTF, mShift);

   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、NoTrendとする。
   if(mTF < PERIOD_CURRENT || mTF > PERIOD_MN1) {
      return NoTrend;
   }

   double EMA_1 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 0), global_Digits);
   double EMA_2 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 1), global_Digits);	
   double EMA_3 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 2), global_Digits);	
   double EMA_4 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 3), global_Digits);	
   double EMA_5 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 4), global_Digits);	
	
/*printf("[%d]COMM トレンド判断get_Trend_EMA %s 時間軸=%d シフト5==%s=%s シフト4==%s=%s シフト3==%s=%s シフト2==%s=%s シフト1==%s=%s", __LINE__,
            TimeToStr(Time[0]),
            mTF,
            TimeToStr(iTime(global_Symbol,mTF, 5)), DoubleToStr(EMA_5, global_Digits),
            TimeToStr(iTime(global_Symbol,mTF, 4)), DoubleToStr(EMA_4, global_Digits),
            TimeToStr(iTime(global_Symbol,mTF, 3)), DoubleToStr(EMA_3, global_Digits),
            TimeToStr(iTime(global_Symbol,mTF, 2)),DoubleToStr(EMA_2, global_Digits),
            TimeToStr(iTime(global_Symbol,mTF, 1)),DoubleToStr(EMA_1, global_Digits));*/
            
            
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
//printf("[%d]COMM トレンド判断不能", __LINE__);
   
      return NoTrend;
   }
   else {
      if(slope > 0.0) {
//printf("[%d]COMM トレンド判断==上昇", __LINE__);
         return UpTrend;
      }
      else if(slope < 0.0) {
//printf("[%d]COMM トレンド判断==下降", __LINE__);
         return DownTrend;
      }
      else {
//printf("[%d]COMM トレンド判断==なし", __LINE__);
      
         return NoTrend;
      }
   }
   return NoTrend;
}


// 4時間足でトレンドを判断する記事が多いことから、追加
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
   double EMA_1 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 0), global_Digits);
   double EMA_2 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 1), global_Digits);	
   double EMA_3 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 2), global_Digits);	
   double EMA_4 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 3), global_Digits);	
   double EMA_5 = NormalizeDouble(iMA(global_Symbol,mTF,14 ,0,MODE_EMA,PRICE_CLOSE,mShift + 4), global_Digits);	
	
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
/*
printf("[%d]COMM , EMA_1, %d, %s, \n EMA_2, %d, %s, \n EMA_3, %d, %s, \n EMA_4, %d, %s, \n EMA_5, %d, %s, \n slope=%s int=%s", __LINE__,
         iTime(global_Symbol,mTF,mShift + 0), DoubleToStr(EMA_1, 5),
         iTime(global_Symbol,mTF,mShift + 1), DoubleToStr(EMA_2, 5),         
         iTime(global_Symbol,mTF,mShift + 2), DoubleToStr(EMA_3, 5),
         iTime(global_Symbol,mTF,mShift + 3), DoubleToStr(EMA_4, 5),
         iTime(global_Symbol,mTF,mShift + 4), DoubleToStr(EMA_5, 5),
         DoubleToStr(slope, 5), DoubleToStr(intercept, 5)
);	
*/
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


// EMAを結ぶ回帰直線の傾きでトレンドを分析する。通貨ペア追加版。
int get_Trend_EMA(string pare, int mTF) {
   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、NoTrendとする。
   if(mTF < PERIOD_CURRENT || mTF > PERIOD_MN1) {
      return NoTrend;
   }

   double EMA_1 = NormalizeDouble(iMA(pare,mTF,14 ,0,MODE_EMA,PRICE_CLOSE, 1), global_Digits);
   double EMA_2 = NormalizeDouble(iMA(pare,mTF,14 ,0,MODE_EMA,PRICE_CLOSE, 2), global_Digits);	
   double EMA_3 = NormalizeDouble(iMA(pare,mTF,14 ,0,MODE_EMA,PRICE_CLOSE, 3), global_Digits);	
   double EMA_4 = NormalizeDouble(iMA(pare,mTF,14 ,0,MODE_EMA,PRICE_CLOSE, 4), global_Digits);	
   double EMA_5 = NormalizeDouble(iMA(pare,mTF,14 ,0,MODE_EMA,PRICE_CLOSE, 5), global_Digits);	

	
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



// アリゲーターを使って、トレンドを計算する
// 入力：通貨ペア、計算する時の時間軸、シフト番号
// 出力：UpTrend(1)上昇傾向、　DownTrend(-1)下落傾向、　NoTrend(0)傾向無し
int get_Trend_Alligator(string mSymbol, 
                        int    mTimeframe,
                        int    mShift
                       ) {
   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、NoTrendとする。
   if(mTimeframe < PERIOD_CURRENT || mTimeframe > PERIOD_MN1) {
      return NoTrend;
   }

   if(mTimeframe < PERIOD_H4) {
      mTimeframe = PERIOD_H4;
   }
   int retTrend = NoTrend;
   //
   // アリゲータによる上昇傾向と下降傾向
   //
   // https://jforexmaster.com/billwilliams-fractals-alligator/
   // ALLIGATOR’S JAW（青） = SMMA ( MIDPOINT PRICE, 13, 8 )
   // ALLIGATOR’S TEETH（赤） = SMMA ( MIDPOINT PRICE, 8, 5 )
   // ALLIGATOR’S LIPS（緑） = SMMA ( MIDPOINT PRICE, 5, 3 )
   // LIPS>TEETH>JAWとなれば上昇トレンド、
   // JAW>TEETH>LIPSとなれば下落トレンドと判断し、
   // これらの状態をアリゲーターが狩りをしていると呼びます。
   double alli_JAW   = iAlligator(global_Symbol,mTimeframe,13,8,8,5,5,3,MODE_SMMA,PRICE_MEDIAN,MODE_GATORJAW  ,mShift);
   double alli_TEETH = iAlligator(global_Symbol,mTimeframe,13,8,8,5,5,3,MODE_SMMA,PRICE_MEDIAN,MODE_GATORTEETH,mShift);
   double alli_LIPS  = iAlligator(global_Symbol,mTimeframe,13,8,8,5,5,3,MODE_SMMA,PRICE_MEDIAN,MODE_GATORLIPS ,mShift);

   // 上昇トレンド
   if( NormalizeDouble(alli_LIPS, global_Digits) >= NormalizeDouble(alli_TEETH, global_Digits)
        && NormalizeDouble(alli_TEETH, global_Digits) >= NormalizeDouble(alli_JAW, global_Digits) ) {
      retTrend = UpTrend;
   }
   // 下降トレンドの時
   if( NormalizeDouble(alli_LIPS, global_Digits) <= NormalizeDouble(alli_TEETH, global_Digits)
        && NormalizeDouble(alli_TEETH, global_Digits) <= NormalizeDouble(alli_JAW, global_Digits) ) {
      retTrend = DownTrend;
   }

   return retTrend;
} 



// EMA25,50,75,100を使って、パーフェクトオーダーの発生状況を計算する
// 入力：過去１～mSpan本でパーフェクトオーダーが発生していることを計算
// 出力：UpTrend(1)上昇傾向、　DownTrend(-1)下落傾向、　NoTrend(0)傾向無し
int get_Trend_PerfectOrder(string mSymbol,  // 通貨ペア
                           int    mTimeframe, // 時間軸。ENUM_TIMEFRAMES型。
                           int    mSpan       // 直近何シフトでパーフェクトオーダーの状態が続いているか
                           ) {
   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、NoTrendとする。
   if(mTimeframe < PERIOD_CURRENT || mTimeframe > PERIOD_MN1) {
      return NoTrend;
   }

   int i;
   int retTrend  = NoTrend;
   int curTrend  = NoTrend;
   int lastTrend = NoTrend;
   double MA_25 = 0.0;
   double MA_50 = 0.0;
   double MA_75 = 0.0;
   double MA_100 = 0.0;
   
   // 高速化を目的として関数呼び出しを減らすため、上昇、下落のパターンをベタ打ちする。
   for(i = 1; i <= mSpan; i++) {
      MA_25 = NormalizeDouble(iMA(mSymbol,mTimeframe,25,0,MODE_EMA,PRICE_CLOSE,i), global_Digits);
      MA_50 = NormalizeDouble(iMA(mSymbol,mTimeframe,50,0,MODE_EMA,PRICE_CLOSE,i), global_Digits);
      // 比較的短期間であるMA25は次の短期間であるMA50との比較に等号を含めない。
      // MA50以降は長期間であり、大きく変化しないことから、比較に等号を含める。
      // 上昇
      if(MA_25 < MA_50 && MA_25 > 0.0) {
         MA_75 = NormalizeDouble(iMA(mSymbol,mTimeframe,75,0,MODE_EMA,PRICE_CLOSE,i), global_Digits);
         
         if(MA_50 <= MA_75 && MA_50 > 0.0) {
            MA_100 = NormalizeDouble(iMA(mSymbol,mTimeframe,100,0,MODE_EMA,PRICE_CLOSE,i), global_Digits);
printf( "[%d]COMM get_Trend_PerfectOrder判定用 MA25=%s < MA50=%s < MA75=%s と右を比較MA100=%s" , __LINE__, 
   DoubleToStr(MA_25, global_Digits),
   DoubleToStr(MA_50, global_Digits),
   DoubleToStr(MA_75, global_Digits),
   DoubleToStr(MA_100, global_Digits)
);
            if(MA_75 <= MA_100 && MA_75 > 0.0) {
               lastTrend = curTrend;
               curTrend = UpTrend;
            }
         }
      }
      // 下落
      else if(MA_25 > MA_50 && MA_50 > 0.0){
         MA_75 = NormalizeDouble(iMA(mSymbol,0,75,0,MODE_EMA,PRICE_CLOSE,i), global_Digits);
         if(MA_50 >= MA_75 && MA_75 > 0.0){
            MA_100 = NormalizeDouble(iMA(mSymbol,0,100,0,MODE_EMA,PRICE_CLOSE,i), global_Digits);
printf( "[%d]COMM get_Trend_PerfectOrder判定用 MA25=%s > MA50=%s < MA75=%s と右を比較MA100=%s" , __LINE__, 
DoubleToStr(MA_25, global_Digits),
DoubleToStr(MA_50, global_Digits),
DoubleToStr(MA_75, global_Digits),
DoubleToStr(MA_100, global_Digits)
);
            
            if(MA_75 >= MA_100 && MA_100 > 0.0){
               lastTrend = curTrend;
               curTrend = DownTrend;
            }
         }
      }
      
      // シフト１の時点でNoTrendならば、中断。lastTrendは設定前のため、比較しない。
      if(i == 1) {
         if(curTrend == NoTrend) {
            retTrend = NoTrend;
            break;
         }
         else {
            retTrend   = curTrend;
            lastTrend  = curTrend; 
         }
      }
      // シフト2以降は、直前のトレンドと変更があれば、中断
      else {
         if(curTrend != lastTrend) {
         
            retTrend = NoTrend;
            break;
         }
         // 同じトレンドが続く限り、返り値は現在のトレンド値curTrendとする。
         else {
            retTrend = curTrend;
         }
      }
   }
  
   return retTrend;
}


// RSIandCCIを使って、トレンドを計算する
int get_Trend_RSIandCCI(int mTimeframe)  {
   int    Avg_Period1 = 8;
   int    Avg_Period2 = 14;
   int    Ind_Period  = 20;
   double Rsi[10];
   double Cci[10];
   double Rsi_MA1;  // シフト1～5のRSIの移動平均
   double Rsi_MA2;  // シフト2～6のRSIの移動平均
   double Cci_MA1;  // シフト1～5のRSIの移動平均
   double Cci_MA2;  // シフト2～6のRSIの移動平均
   
   int timeFrame = mTimeframe; 
   int mlimit = 5;
   int i = 0;
   
   ArrayInitialize(Rsi, 0.0);
   ArrayInitialize(Cci, 0.0);

   
   // シフト1～6の値を取得する。
   for(i = 1; i <= mlimit+1; i++) {
      Rsi[i]=iRSI(global_Symbol,timeFrame,Ind_Period,PRICE_CLOSE,i);
   }
   // シフト1～6の値を取得する。
   for(i = 1; i <= mlimit+1; i++) {
      Cci[i]=iCCI(global_Symbol,timeFrame,Ind_Period,PRICE_CLOSE,i);
   }
   
   // シフト1～6のRSIを使ってRSI_MA1の移動平均を計算
   Rsi_MA1 = 0.0;
   for(i = 1; i <= mlimit; i++) {
      Rsi_MA1 = Rsi_MA1 + NormalizeDouble(Rsi[i], global_Digits);
   }
   Rsi_MA1 = Rsi_MA1 / mlimit;

   // シフト2～6のRSIを使ってRSI_MA1の移動平均を計算
   Rsi_MA2 = 0.0;
   for(i = 2; i <= mlimit+1; i++) {
      Rsi_MA2 = Rsi_MA2 + NormalizeDouble(Rsi[i], global_Digits);
   }
   Rsi_MA2 = Rsi_MA2 / mlimit;
    
   // シフト1～6のRSIを使ってRSI_MA1の移動平均を計算
   Cci_MA1 = 0.0;
   for(i = 1; i <= mlimit; i++) {
      Cci_MA1 = Cci_MA1 + NormalizeDouble(Cci[i], global_Digits);
   }
   Cci_MA1 = Cci_MA1 / mlimit;

   // シフト2～6のRSIを使ってRSI_MA1の移動平均を計算
   Cci_MA2 = 0.0;
   for(i = 2; i <= mlimit+1; i++) {
      Cci_MA2 = Cci_MA2 + NormalizeDouble(Cci[i], global_Digits);
   }
   Cci_MA2 = Cci_MA2 / mlimit;

   
   // https://fx-quicknavi.com/chart/rsi/
   // 基本的な見方ですが、50%を中立の基準として、50%以上で上昇していれば上昇パワーが強く、50%以下で下降していれば下降パワーが強いと見ることができます。
   
   // https://fx-quicknavi.com/chart/cci/
   // CCIは0（ゼロライン）の交差でトレンドの転換とします。0より上で上昇トレンド、0より下で下降トレンドと判断ができます。
//printf("[%d]COMM RSIとCCIの値を検証すること Rsi_MA1=%s Cci_MA1=%s", __LINE__, DoubleToStr(Rsi_MA1), DoubleToStr(Cci_MA1));
   
   if(NormalizeDouble(Rsi_MA1, global_Digits) >=  NormalizeDouble(Rsi_MA2, global_Digits) 
      && Rsi_MA1 > 50.0
      && NormalizeDouble(Cci_MA1, global_Digits) >= NormalizeDouble(Cci_MA2, global_Digits)
      && Cci_MA1 > 0.0 ) {
       return UpTrend;
   } 
   else if(NormalizeDouble(Rsi_MA1, global_Digits) < NormalizeDouble(Rsi_MA2, global_Digits)
           && Rsi_MA1 < 50.0
           && NormalizeDouble(Cci_MA1, global_Digits) < NormalizeDouble(Cci_MA2, global_Digits)
           && Cci_MA1 < 0.0 ) {
	return DownTrend;
   }
   else {
      return NoTrend;	
   }

   return(NoTrend);
}


// 複数のトレンド分析関数を使って、上昇、下落、トレンド無しの判断を
// した件数を返す。
bool get_Trend_Combo(string mSymbol,      // 通貨ペア 
                     int    mTimeframe,    // 時間軸
                     int    mShift,        // シフト
                     int    &UpTrend_Num,  // 出力：UpTrend上昇傾向にあると判断した数
                     int    &DownTrend_Num,// 出力：DownTrend下落傾向にあると判断した数
                     int    &NoTrend_Num   // 出力：NoTrend傾向無し判断した数
 ){ 
   UpTrend_Num   = 0;
   DownTrend_Num = 0;
   NoTrend_Num   = 0;

   // 引数が、PERIOD_CURRENT(=0)未満又はPERIOD_MN1(=43200)より大きい時は、判断不能とする。
   if(mTimeframe < PERIOD_CURRENT || mTimeframe > PERIOD_MN1) {
      return false;
   }



   int bufTrend = NoTrend;

   //
   // get_Trend_EMAを使ったトレンド判断
   // 
   bufTrend = get_Trend_EMA(mTimeframe);
   if(bufTrend == UpTrend ) { 
      UpTrend_Num++;
   }
   else if(bufTrend == DownTrend ) {
      DownTrend_Num++;
   }
   else {
      NoTrend_Num++;
   }

   //
   // get_Trend_Alligatorを使ったトレンド判断
   // 
   bufTrend = 
   get_Trend_Alligator(mSymbol, 
                       mTimeframe,
                       mShift
                       );
   if(bufTrend == UpTrend ) { 
      UpTrend_Num++;
   }
   else if(bufTrend == DownTrend ) {
      DownTrend_Num++;
   }
   else {
      NoTrend_Num++;
   }

   //
   // get_Trend_PerfectOrderを使ったトレンド判断
   // 
   bufTrend = get_Trend_PerfectOrder(mSymbol,    // 通貨ペア
                                     mTimeframe, // 時間軸
                                     2           // 簡単にするため2とした。直近何シフトでパーフェクトオーダーの状態が続いているか
                                   ); 
   if(bufTrend == UpTrend ) { 
      UpTrend_Num++;
   }
   else if(bufTrend == DownTrend ) {
      DownTrend_Num++;
   }
   else {
      NoTrend_Num++;
   }


   //
   // get_Trend_RSIandCCIを使ったトレンド判断
   // 
   bufTrend = get_Trend_RSIandCCI(mTimeframe);
   if(bufTrend == UpTrend ) { 
      UpTrend_Num++;
   }
   else if(bufTrend == DownTrend ) {
      DownTrend_Num++;
   }
   else {
      NoTrend_Num++;
   }

   return true;  
}




// 引数で渡す通貨ペア、時間軸、バーの開始時間、価格をキーとして、1分足で何分に発生したことになっているかを返す。
// 計算失敗時は、0を返す。
datetime get_TimeAtPeriodM1(string   mSymbol,         //　通貨ペア名
                            int      mSourceTimeframe,// 価格を取得した時の時間軸
                            datetime mTargetTime,     // 価格を取得した時のバーの開始時間
                            double   mTargetPrice,    // 検索する価格
                            int      mClass           // 始値(OPEN_PRICE)、高値(HIGH_PRICE)、安値(LOW_PRICE)、終値(CLOSE_PRICE)のいずれで検索するか。 
                            ) {
   if(mSourceTimeframe == 0) {
      mSourceTimeframe = Period();
   }                            
   if(StringLen(mSymbol) <= 0) {
printf( "[%d]COMM 通貨ペア不正" , __LINE__);
   
      return 0;
   }
   if(checkTimeFrame(mSourceTimeframe) != true) {
printf( "[%d]COMM 時間軸不正" , __LINE__);      
      return 0;
   }
   if(mTargetTime <= 0) {
printf( "[%d]COMM 対象時間不正 mTargetTime=%d" , __LINE__, mTargetTime);   
      return 0;
   }
   if(mTargetPrice <= 0.0) {
printf( "[%d]COMM 検索する価格不正" , __LINE__);   
      return 0;
   }
   if(mClass < OPEN_PRICE || mClass > CLOSE_PRICE) {
printf( "[%d]COMM 分類不正" , __LINE__);   
      return 0;
   }
   
   int timeLen = (int)mSourceTimeframe; // 単位は、分。ENUM_TIMEFRAMESは、PERIOD_M15＝１５など、何分かを指していることから、時間軸が何分間かの値に使う。
//printf( "[%d]COMM 何シフト前まで戻るか = %d" , __LINE__, timeLen);   
   
   int i;
   double   bufPrice = 0.0; // 検索中に取得した価格
   int      sourceShift = 0;    // 引数渡しされた時間を含むバー（引数渡しされた時間軸）のシフト番号。
   datetime sourceOpenTime = 0; // sourceShiftを使って計算しなおした検索開始時刻
   int      startShift_M1 = 0;  // sourceOpenTimeを含むバー（時間軸は、PERIOD_M1）のシフト番号
   datetime resultTime = 0;     // 1分足で、引数渡しされた値を含むバーの開始時刻。
   sourceShift = iBarShift(mSymbol, mSourceTimeframe, mTargetTime, false); // 引数mTargetTimeを含む時間軸mSourceTimeframeのシフト
   if(sourceShift < 0) {
      return 0;
   }
   
   sourceOpenTime = iTime(mSymbol, mSourceTimeframe, sourceShift); 
   
   if(sourceOpenTime <= 0) {
      return 0;
   }
   
   startShift_M1  = iBarShift(mSymbol, PERIOD_M1, sourceOpenTime, false); 
   if(startShift_M1 < 0) {
      return 0;
   }
   
   bool flag_Match = false;
  
   for(i = 0; i <= timeLen; i++) {
      // PERIOD_M1の４値のうち、いずれかを取得する。
      if(mClass == OPEN_PRICE) {
         bufPrice = NormalizeDouble(iOpen(mSymbol, PERIOD_M1, startShift_M1 - i), global_Digits);
      }
      else if(mClass == HIGH_PRICE) {
         bufPrice = NormalizeDouble(iHigh(mSymbol, PERIOD_M1, startShift_M1 - i), global_Digits);         
      }
      else if(mClass == LOW_PRICE) {
         bufPrice = NormalizeDouble(iLow(mSymbol, PERIOD_M1, startShift_M1 - i), global_Digits);      
      }
      else if(mClass == CLOSE_PRICE) {
         bufPrice = NormalizeDouble(iClose(mSymbol, PERIOD_M1, startShift_M1 - 1), global_Digits);      
      }
      else {
         return 0;
      }
      
      // 引数で渡された値mTargetPriceと取得したPERIOD＿M1の値が一致すれば、フラグflag_Matchをtrueにして、ループを抜ける
      if( NormalizeDouble(bufPrice, global_Digits) == NormalizeDouble(mTargetPrice, global_Digits) ) {
         flag_Match = true;
         resultTime = iTime(mSymbol, PERIOD_M1, startShift_M1 - i);
         break;
      }
   }

   // 正常終了時の処理
   if(flag_Match == true) {
      if(resultTime > 0) {
         return resultTime;
      }
   }   
   
   // 異常終了時の処理
   return 0;
}



//+-------------------------------------------+
//| FRACTALを使って値を取得する関数群         |
//+-------------------------------------------+
//　実行した時点でのフラクタル値を計算し、構造体である引数にセットする。
bool get_Fractals(st_Fractal &m_st_Fractals[]  // 出力用
   ) {
   int i;
   // 構造体変数の初期化
   for(i = 0; i < FRAC_NUMBER; i++) {
      m_st_Fractals[i].type     = FRAC_NONE; // 山か谷か。FRAC_MOUNT、FRAC_BOTTOM、FRAC_NONE
      m_st_Fractals[i].value    = DOUBLE_VALUE_MIN; // フラクタルの値
      m_st_Fractals[i].shift    = INT_VALUE_MIN;    // フラクタル発生時のシフト番号
      m_st_Fractals[i].calcTime = 0;                // PERIOD_M1を用いて計算したフラクタル（山）発生時刻 
   }
//printf( "[%d]COMM get_Fractals" , __LINE__);

   int j = 0;
   double bufFracval = 0.0;
   datetime bufDT = 0;    // PERIOD_M1で発生時刻を計算する際の一時避難
   int fracCount = 0;  // 発見した山または谷の個数。
   // 直近のフラクタルの山を2つ取得する。
   for(i = 1; i <= FRACTALSPAN;i++) {
      bufFracval = NormalizeDouble(iFractals(global_Symbol, global_Period, MODE_UPPER, i), global_Digits);
      if(bufFracval > 0.0) {
         for(j = 0; j < FRAC_NUMBER; j++) {
            if(m_st_Fractals[j].type == FRAC_NONE 
               || (m_st_Fractals[j].type != FRAC_MOUNT && m_st_Fractals[j].type != FRAC_BOTTOM)) { 
               m_st_Fractals[j].type      = FRAC_MOUNT;
               m_st_Fractals[j].value     = bufFracval;
               m_st_Fractals[j].shift     = i;                                     // 注目しているシフト番号
               m_st_Fractals[j].calcTime  = iTime(global_Symbol, global_Period, i);// 注目しているシフト番号の開始時刻

               bufDT = get_TimeAtPeriodM1(global_Symbol,           //　通貨ペア名
                                          global_Period,           // 価格を取得した時の時間軸
                                          m_st_Fractals[j].calcTime, // 価格を取得した時のバーの開始時間
                                          m_st_Fractals[j].value,    // 検索する価格
                                          HIGH_PRICE);             // 始値(OPEN_PRICE)、高値(HIGH_PRICE)、安値(LOW_PRICE)、終値(CLOSE_PRICE)のいずれで検索するか。 
               if(bufDT > 0) {
                  m_st_Fractals[j].calcTime = bufDT;
               }
               fracCount++;
               break;  // j　のループから脱出
            }
         }
      }
      if(fracCount > 3) {
         break;
      }
   }	

   bufFracval = 0.0;
   bufDT = 0;
   fracCount = 0;
   // 直近のフラクタルの谷を2つ取得する。
   for(i = 1; i <= FRACTALSPAN;i++) {
      bufFracval = NormalizeDouble(iFractals(global_Symbol, global_Period, MODE_LOWER, i), global_Digits);
      if(bufFracval > 0.0) {      
         for(j = 0; j < FRAC_NUMBER; j++) {
            if(m_st_Fractals[j].type == FRAC_NONE 
               || (m_st_Fractals[j].type != FRAC_MOUNT && m_st_Fractals[j].type != FRAC_BOTTOM)) { 
               m_st_Fractals[j].type      = FRAC_BOTTOM;
               m_st_Fractals[j].value     = bufFracval;
               m_st_Fractals[j].shift     = i;                                     // 注目しているシフト番号
               m_st_Fractals[j].calcTime  = iTime(global_Symbol, global_Period, i);// 注目しているシフト番号の開始時刻

               bufDT = get_TimeAtPeriodM1(global_Symbol,           //　通貨ペア名
                                          global_Period,           // 価格を取得した時の時間軸
                                          m_st_Fractals[j].calcTime, // 価格を取得した時のバーの開始時間
                                          m_st_Fractals[j].value,    // 検索する価格
                                          LOW_PRICE);              // 始値(OPEN_PRICE)、高値(HIGH_PRICE)、安値(LOW_PRICE)、終値(CLOSE_PRICE)のいずれで検索するか。 
               if(bufDT > 0) {
                  m_st_Fractals[j].calcTime = bufDT;
               }
               fracCount++;
               break;  // j　のループから脱出
            }
         }
      }
      if(fracCount > 3) {
         break;
      }
   }
  
/*  
printf( "[%d]COMM 関数get_Fractals内の結果は以下の通り", __LINE__);
datetime firstMOUNT = -1;
double   firstMOUNTvalue = 0.0;
datetime firstBOTTOM = -1;
double   firstBOTTOMvalue = 0.0;

for(i = 0; i < FRAC_NUMBER; i++) {
   if(m_st_Fractals[i].type == FRAC_MOUNT || m_st_Fractals[i].type == FRAC_BOTTOM) {
      if(m_st_Fractals[i].type == FRAC_MOUNT) {
         // 後で直近の山を表示するため、直近の山を取得する。
         if(firstMOUNT < 0) {
            firstMOUNT = i;
         }
         printf( "[%d]COMM st_Fractals[%d] type=山 val=%s シフト=%d 時刻=%s" , __LINE__,
                  i, 
                  DoubleToStr(m_st_Fractals[i].value, global_Digits),
                  m_st_Fractals[i].shift, 
                  TimeToStr(m_st_Fractals[i].calcTime)
               );
      }
      else if(m_st_Fractals[i].type == FRAC_BOTTOM) {
         // 後で直近の谷を表示するため、直近の谷を取得する。
         if(firstBOTTOM < 0) {
            firstBOTTOM = i;
         }
      
         printf( "[%d]COMM st_Fractals[%d] type=谷 val=%s シフト=%d 時刻=%s" , __LINE__,
                  i, 
                  DoubleToStr(m_st_Fractals[i].value, global_Digits),
                  m_st_Fractals[i].shift, 
                  TimeToStr(m_st_Fractals[i].calcTime)
               );
      }
   }
}
if(m_st_Fractals[firstBOTTOM].calcTime > m_st_Fractals[firstMOUNT].calcTime) {
  printf( "[%d]COMM 直近は谷　　山=シフト=%d %d==%s=>%s<" , __LINE__,firstMOUNT,  m_st_Fractals[firstMOUNT].calcTime, TimeToStr(m_st_Fractals[firstMOUNT].calcTime),   DoubleToStr(m_st_Fractals[firstMOUNT].value, global_Digits));
  printf( "[%d]COMM 直近は谷　　谷=シフト=%d %d==%s=>%s<" , __LINE__,firstBOTTOM, m_st_Fractals[firstBOTTOM].calcTime, TimeToStr(m_st_Fractals[firstBOTTOM].calcTime), DoubleToStr(m_st_Fractals[firstBOTTOM].value, global_Digits));
}
else if(m_st_Fractals[firstBOTTOM].calcTime < m_st_Fractals[firstMOUNT].calcTime) {
  printf( "[%d]COMM 直近は山　　山=シフト=%d %d==%s=>%s<" , __LINE__,firstMOUNT,  m_st_Fractals[firstMOUNT].calcTime, TimeToStr(m_st_Fractals[firstMOUNT].calcTime), DoubleToStr(m_st_Fractals[firstMOUNT].value, global_Digits));
  printf( "[%d]COMM 直近は山　　谷=シフト=%d %d==%s=>%s<" , __LINE__,firstBOTTOM, m_st_Fractals[firstBOTTOM].calcTime, TimeToStr(m_st_Fractals[firstBOTTOM].calcTime), DoubleToStr(m_st_Fractals[firstBOTTOM].value, global_Digits));
}
*/

   return true;
}

//　引数のフラクタル配列m_st_Fractalsの中から、引数mTypeで指定した山又は谷の、引数mNum番目が入っている
//  配列の項番を返す。
int get_FractalsIndex(st_Fractal &m_st_Fractals[],  // 検索対象の配列
                      int mType,                  // 探すのが山か谷か。FRAC_MOUNT、FRAC_BOTTOM、FRAC_NONE 
                      int mNum                    // 何番目を探しているか。
                      ) {
   int i;
   int numMount  = 0;  // 配列の中で登場した山の数
   int numBottom = 0;  // 配列の中で登場した谷の数

   for(i = 0; i < FRAC_NUMBER; i++) {
      if(m_st_Fractals[i].type == mType) {
         if(m_st_Fractals[i].type == FRAC_MOUNT) {
            numMount++;
         }
         else if(m_st_Fractals[i].type == FRAC_BOTTOM) {
            numBottom++;
         }
 
         if(mType == FRAC_MOUNT  && numMount == mNum) {
//  printf( "[%d]COMM %d番目の山のインデックスは、%d" , __LINE__, mNum, i);
         
            return i;
         }
         if(mType == FRAC_BOTTOM && numBottom == mNum) {
//  printf( "[%d]COMM %d番目の谷のインデックスは、%d" , __LINE__, mNum, i);
            return i;
         }
      }
   }

   return INT_VALUE_MIN;
}


// フラクタル値を格納する構造体st_Fractal配列のうち、山、谷を各3つずつ読み込んで、引数に値を設定する。
bool read_FracST_TO_Param(st_Fractal &m_st_Fractals[], // 入力：読み込む構造体
   double &m_Fractals_UPPER1_y,      // 出力：直近のフラクタル値(UPPER)
   int    &m_Fractals_UPPER1_x,      // 出力：直近のフラクタル値(UPPER)のシフト値
   datetime &m_Fractals_UPPER1_time, // 出力：フラクタルを取得したシフト値のTime

   double &m_Fractals_UPPER2_y,      // 出力：2つ目のフラクタル値(UPPER)
   int    &m_Fractals_UPPER2_x,      // 出力：2つ目のフラクタル値(UPPER)のシフト値
   datetime &m_Fractals_UPPER2_time, // 出力：フラクタルを取得したシフト値のTime

   double &m_Fractals_UPPER3_y,      // 出力：2つ目のフラクタル値(UPPER)
   int    &m_Fractals_UPPER3_x,      // 出力：2つ目のフラクタル値(UPPER)のシフト値
   datetime &m_Fractals_UPPER3_time, // 出力：フラクタルを取得したシフト値のTime

   double &m_Fractals_LOWER1_y,      // 出力：直近のフラクタル値(LOWER)
   int    &m_Fractals_LOWER1_x,      // 出力：直近のフラクタル値(LOWER)のシフト値
   datetime &m_Fractals_LOWER1_time, // 出力：フラクタルを取得したシフト値のTime

   double &m_Fractals_LOWER2_y,      // 出力：2つ目のフラクタル値(LOWER)
   int    &m_Fractals_LOWER2_x,      // 出力：2つ目のフラクタル値(LOWER)のシフト値
   datetime &m_Fractals_LOWER2_time, // 出力：フラクタルを取得したシフト値のTime   

   double &m_Fractals_LOWER3_y,      // 出力：2つ目のフラクタル値(LOWER)
   int    &m_Fractals_LOWER3_x,      // 出力：2つ目のフラクタル値(LOWER)のシフト値
   datetime &m_Fractals_LOWER3_time  // 出力：フラクタルを取得したシフト値のTime  
   ) {
   int bufIndex = -1;
   bufIndex = get_FractalsIndex(m_st_Fractals,  // 検索対象の配列
                                FRAC_MOUNT,     // 探すのが山か谷か。FRAC_MOUNT、FRAC_BOTTOM、FRAC_NONE 
                                1               // 何番目を探しているか。
                     );
   if(bufIndex >= 0) {
      m_Fractals_UPPER1_y     = NormalizeDouble(m_st_Fractals[bufIndex].value, global_Digits);
      m_Fractals_UPPER1_x     = m_st_Fractals[bufIndex].shift;
      m_Fractals_UPPER1_time  = m_st_Fractals[bufIndex].calcTime;
   }

   bufIndex = get_FractalsIndex(m_st_Fractals,  // 検索対象の配列
                                FRAC_MOUNT,     // 探すのが山か谷か。FRAC_MOUNT、FRAC_BOTTOM、FRAC_NONE 
                                2               // 何番目を探しているか。
                     );
   if(bufIndex >= 0) {
      m_Fractals_UPPER2_y     = NormalizeDouble(m_st_Fractals[bufIndex].value, global_Digits); 
      m_Fractals_UPPER2_x     = m_st_Fractals[bufIndex].shift;
      m_Fractals_UPPER2_time  = m_st_Fractals[bufIndex].calcTime;
   }      

   bufIndex = get_FractalsIndex(m_st_Fractals,  // 検索対象の配列
                                FRAC_MOUNT,     // 探すのが山か谷か。FRAC_MOUNT、FRAC_BOTTOM、FRAC_NONE 
                                3               // 何番目を探しているか。
                     );
   if(bufIndex >= 0) {
      m_Fractals_UPPER3_y     = NormalizeDouble(m_st_Fractals[bufIndex].value, global_Digits); 
      m_Fractals_UPPER3_x     = m_st_Fractals[bufIndex].shift;
      m_Fractals_UPPER3_time  = m_st_Fractals[bufIndex].calcTime;
   }
       
   bufIndex = get_FractalsIndex(m_st_Fractals,  // 検索対象の配列
                                FRAC_BOTTOM,    // 探すのが山か谷か。FRAC_BOTTOM、FRAC_BOTTOM、FRAC_NONE 
                                1               // 何番目を探しているか。
                     );
   if(bufIndex >= 0) {
//   printf( "[%d]COMM １つ目の谷m_st_Fractals[%d] = %s" , __LINE__, bufIndex, DoubleToStr(m_st_Fractals[bufIndex].value, global_Digits));
      m_Fractals_LOWER1_y     = NormalizeDouble(m_st_Fractals[bufIndex].value, global_Digits);
      m_Fractals_LOWER1_x     = m_st_Fractals[bufIndex].shift;
      m_Fractals_LOWER1_time  = m_st_Fractals[bufIndex].calcTime;
   }
   else {
      printf( "[%d]COMM m_Fractals_LOWER1_y見つからず。" , __LINE__);
   }

   bufIndex = get_FractalsIndex(m_st_Fractals,  // 検索対象の配列
                                FRAC_BOTTOM,    // 探すのが山か谷か。FRAC_BOTTOM、FRAC_BOTTOM、FRAC_NONE 
                                2               // 何番目を探しているか。
                     );
   if(bufIndex >= 0) {
//printf( "[%d]COMM 2つ目の谷m_st_Fractals[%d] = %s" , __LINE__, bufIndex, DoubleToStr(m_st_Fractals[bufIndex].value, global_Digits));
      m_Fractals_LOWER2_y     = NormalizeDouble(m_st_Fractals[bufIndex].value, global_Digits); 
      m_Fractals_LOWER2_x     = m_st_Fractals[bufIndex].shift;
      m_Fractals_LOWER2_time  = m_st_Fractals[bufIndex].calcTime;
   }

   bufIndex = get_FractalsIndex(m_st_Fractals,  // 検索対象の配列
                                FRAC_BOTTOM,    // 探すのが山か谷か。FRAC_BOTTOM、FRAC_BOTTOM、FRAC_NONE 
                                3               // 何番目を探しているか。
                     );
   if(bufIndex >= 0) {
//   printf( "[%d]COMM ３つ目の谷m_st_Fractals[%d] = %s" , __LINE__, bufIndex, DoubleToStr(m_st_Fractals[bufIndex].value, global_Digits));
      m_Fractals_LOWER3_y     = NormalizeDouble(m_st_Fractals[bufIndex].value, global_Digits); 
      m_Fractals_LOWER3_x     = m_st_Fractals[bufIndex].shift;
      m_Fractals_LOWER3_time  = m_st_Fractals[bufIndex].calcTime;
   }  
  if(bufIndex < 0) {
     return false;
  }
  
  return true;
}


// ロングの損切値をFRACの谷から探すための関数
// FRACの谷のうち、引数mShiftFromより過去で、最初に引数mTargetを下回った値を返す。
double get_Next_Lower_FRAC(string mSymbol,    // 通貨ペア
                           int    mTimeframe, // タイムフレーム 
                           int    mShiftFrom, // このシフト＋１以上のシフトでFractalを計算する。
                           double mTarget     // この値より小さな値を探す
                                       ) {
                                       
   int i;
   double bufNext = DOUBLE_VALUE_MIN;
   for(i = mShiftFrom + 1; i < FRACTALSPAN*10; i++) {
      bufNext = NormalizeDouble(iFractals(mSymbol, mTimeframe, MODE_LOWER, i), global_Digits);
      if(bufNext > 0.0 && NormalizeDouble(mTarget, global_Digits) > NormalizeDouble(bufNext, global_Digits) ){
//printf( "[%d]COMM get_Next_Lower_FRACで探した次の谷=%s" , __LINE__, DoubleToStr(bufNext, global_Digits)); 
      
         return NormalizeDouble(bufNext, global_Digits);
      }
   }

//printf( "[%d]COMM get_Next_Lower_FRACで探した次の谷が見つからず=%s" , __LINE__, DoubleToStr(DOUBLE_VALUE_MIN, global_Digits));    
   return DOUBLE_VALUE_MIN;
}

// ショートの損切値をFRACの山から探すための関数
// FRACの山のうち、引数mShiftFromより過去で、最初に引数mTargetを上回った値を返す。
double get_Next_Upper_FRAC(string mSymbol,    // 通貨ペア
                           int    mTimeframe, // タイムフレーム 
                           int    mShiftFrom, // このシフト＋１以上のシフトでFractalを計算する。
                           double mTarget     // この値より小さな値を探す
                                       ) {
//printf( "[%d]COMM get_Next_Upper_FRACで探す" , __LINE__); 
                                       
   int i;
   double bufNext = DOUBLE_VALUE_MIN;
   for(i = mShiftFrom + 1; i < FRACTALSPAN*10; i++) {
      bufNext = NormalizeDouble(iFractals(mSymbol, mTimeframe, MODE_UPPER, i), global_Digits);
      if(bufNext > 0.0 && NormalizeDouble(mTarget, global_Digits) < NormalizeDouble(bufNext, global_Digits) ){
//printf( "[%d]COMM get_Next_Upper_FRACで探した次の山=%s" , __LINE__, DoubleToStr(bufNext, global_Digits)); 
      
         return NormalizeDouble(bufNext, global_Digits);
      }
   }
//printf( "[%d]COMM get_Next_Lower_FRACで探した次の山が見つからず=%s" , __LINE__, DoubleToStr(DOUBLE_VALUE_MIN, global_Digits));    
   
   return DOUBLE_VALUE_MIN;
}



bool calc_ModifyablePrice(int    mBuySell,     // OP_BUY, OPSELL
                          double mMarketinfoMODE_BID, // 計算時点のBid
                          double mMarketinfoMODE_ASK, // 計算時点のAsk
                          double &mTPable_Price, // OP_BUYの時は、利確できる最小値。OP_SELLの時は、利確できる最大値
                          double &mSLable_Price) // OP_BUYの時は、損切できる最大値。OP_SELLの時は、損切できる最小値
   {
   if(mBuySell != OP_BUY && mBuySell != OP_SELL) {
      return false;
   }                          

   mTPable_Price = DOUBLE_VALUE_MIN;
   mSLable_Price = DOUBLE_VALUE_MIN;
   
   if(mBuySell == OP_BUY) {
      mTPable_Price = NormalizeDouble(mMarketinfoMODE_ASK  + global_StopLevel, global_Digits);
      mSLable_Price = NormalizeDouble(mMarketinfoMODE_BID  - global_StopLevel, global_Digits);
   }
   else if(mBuySell == OP_SELL) {
      mTPable_Price = NormalizeDouble(mMarketinfoMODE_BID - global_StopLevel, global_Digits);
      mSLable_Price = NormalizeDouble(mMarketinfoMODE_ASK + global_StopLevel, global_Digits);
   }
   
   return true;
}


// 関数update_AllOrdersTPSLの実行対象外とする文字列が引数mCommentに入っていれば、true
bool avoid_update_AllOrdersTPSL(string mComment) {
   bool ret = false;

   if(StringFind(mComment, g_StratName01, 0) >= 0) { // g_StratName01=Frac
      ret = true;
   }
/*   if(StringFind(mComment, g_StratName24, 0) >= 0) { // g_StratName24=Zigzag
      ret = true;
   }
*/
   return ret;
}


// 引数のask及びbid各々が、オープン中の取引の建値が引数の誤差範囲（約定間隔20pips*許容誤差10%なら差が2PIPSまでは同じ約定値）ならば、
// ほぼ同じ取引が既に存在すると判断して、trueを返す。
// 該当する取引が無ければ、falseを返す
//// オープン中の取引がショートの場合は、その建値と引数のmBidを比較する。
//// オープン中の取引がロングの場合は、その建値と引数のmAskを比較する。
bool isExistingNearOpenPrices(int magic,              // マジックナンバー
                              double mAllowDiff_PIPS, // 許容できる誤差
                              double mBid,            // ショート用価格
                              double mAsk ) {         // ロング用価格
   int i;
   double n_mAllowDiff_PIPS = NormalizeDouble(mAllowDiff_PIPS, global_Digits * 2);
   double n_mBid = NormalizeDouble(mBid, global_Digits);
   double n_mAsk = NormalizeDouble(mAsk, global_Digits);
   
   if(mAllowDiff_PIPS < 0) {
      return false;
   }
printf( "[%d]COM read_OpenTrades実行" , __LINE__);   
   
read_OpenTrades(magic);
   int buysell = INT_MIN;
   double openPrice = DOUBLE_VALUE_MIN;
   bool flag_existSell = false;
   bool flag_existBuy  = false;
   double bufAllowDiff_PIPS = DOUBLE_VALUE_MIN;
   for(i = 0; i < MAX_TRADE_NUM; i++) {
      if(OpenTrade_BuySell[i] <= INT_MIN
         || (OpenTrade_BuySell[i] != OP_SELL && OpenTrade_BuySell[i] != OP_BUY)) {
         break;
      }

      if(OpenTrade_BuySell[i] == OP_SELL) {
         openPrice = NormalizeDouble(OpenTrade_OpenPrice[i], global_Digits);
         // 
         bufAllowDiff_PIPS = NormalizeDouble(MathAbs( change_Point2PIPS(openPrice - n_mBid) ), global_Digits);
         
         if(bufAllowDiff_PIPS <= n_mAllowDiff_PIPS) {
            flag_existSell = true;
         }
         bufAllowDiff_PIPS = DOUBLE_VALUE_MIN;
      }
      else if(OpenTrade_BuySell[i] == OP_BUY) {
         openPrice = NormalizeDouble(OpenTrade_OpenPrice[i], global_Digits);
         bufAllowDiff_PIPS = NormalizeDouble(MathAbs( change_Point2PIPS(openPrice - n_mAsk) ), global_Digits);
         if(bufAllowDiff_PIPS <= n_mAllowDiff_PIPS) {
            flag_existBuy = true;
         }
         bufAllowDiff_PIPS = DOUBLE_VALUE_MIN;
      }
      
      if(flag_existSell == true && flag_existBuy == true) {
         return true;
      }
   }
   return false;
}

/* 20221227
// 引数のマジックナンバーで、ロング又はショートを、mNewPriceで発注できれば、true。それ以外は、false
// 1) 発注予定価格mNewPriceが、取引可能な価格の範囲であること
// 2) 発注予定価格mNewPrice＋ENTRY_WIDTH_PIPS±許容誤差に同じ売買種別の取引があれば、false
// 3) 発注予定価格mNewPriceーENTRY_WIDTH_PIPS±許容誤差に同じ売買種別の取引があれば、false
bool is_TradablePrice(int magic,               // マジックナンバー
                      int mBuySell,            // 売買区分
                      double mTradableMax,     // 取引可能上限（グローバル変数のg_long_Maxなど）
                      double mTradableMin,     // 取引可能下限（グローバル変数のg_long_Minなど）
                      double mAllowDiff_PIPS,  // 何PIPSの誤差を許容するのか
                      double mNewPrice) {      // 発注しようとしている価格
   double n_mTradableMax    = NormalizeDouble(mTradableMax, global_Digits); 
   double n_mTradableMin    = NormalizeDouble(mTradableMin, global_Digits);
   double n_mAllowDiff_PIPS = NormalizeDouble(mAllowDiff_PIPS, global_Digits);
   double n_mNewPrice       = NormalizeDouble(mNewPrice, global_Digits);
   int i;

   // 1) 発注予定価格mNewPriceが、取引可能な価格の範囲であること
   if(n_mNewPrice > n_mTradableMax || n_mNewPrice < n_mTradableMin) {



string bufBuySell;
if(mBuySell == BUY_SIGNAL) {
   bufBuySell = "ロング";
}
else if(mBuySell == SELL_SIGNAL) {
   bufBuySell = "ショート";
}
else {
   bufBuySell = "不明";
}

      return false;
   }


   double n_mNewPrice_Upper; // 発注予定価格 +　ENTRY_WIDTH_PIPS
   double n_mNewPrice_Lower; // 発注予定価格 -  ENTRY_WIDTH_PIPS
   double n_bufOpenTrade_OpenPrice; // OpenTrade_OpenPrice[i] をNormalizeDouble化した値段
   double bufDiff_PIPS_Upper;
   double bufDiff_PIPS_Lower;
printf( "[%d]COM read_OpenTrades実行" , __LINE__);   

read_OpenTrades(magic);

   // 2) 発注予定価格n_mNewPrice＋ENTRY_WIDTH_PIPS±許容誤差に同じ売買種別の取引があれば、false
   // 3) 発注予定価格mNewPrice - ENTRY_WIDTH_PIPS±許容誤差に同じ売買種別の取引があれば、false
   for(i = 0; i < MAX_TRADE_NUM; i++) {
      if(OpenTrade_BuySell[i] <= INT_MIN
         || (OpenTrade_BuySell[i] != OP_SELL && OpenTrade_BuySell[i] != OP_BUY)) {
         break;
      }
      
           
      // 発注予定価格よりENTRY_WIDTH_PIPS上の価格　→　この誤差範囲に、オープン中取引があれば、falseを返す
      n_mNewPrice_Upper = n_mNewPrice + NormalizeDouble(change_PiPS2Point(ENTRY_WIDTH_PIPS), global_Digits) ;
      // 発注予定価格よりENTRY_WIDTH_PIPS下の価格　→　この誤差範囲に、オープン中取引があれば、falseを返す
      n_mNewPrice_Lower = n_mNewPrice - NormalizeDouble(change_PiPS2Point(ENTRY_WIDTH_PIPS), global_Digits) ;
      // オープン中取引の値
      n_bufOpenTrade_OpenPrice = NormalizeDouble(OpenTrade_OpenPrice[i], global_Digits); 

      // 誤差
      bufDiff_PIPS_Upper = NormalizeDouble(MathAbs( change_Point2PIPS(n_bufOpenTrade_OpenPrice - n_mNewPrice_Upper)), global_Digits);
      bufDiff_PIPS_Lower = NormalizeDouble(MathAbs( change_Point2PIPS(n_bufOpenTrade_OpenPrice - n_mNewPrice_Lower)), global_Digits);

      double allowableDiff_PIPS = NormalizeDouble(ENTRY_WIDTH_PIPS * ALLOWABLE_DIFF_PER / 100.0, global_Digits); // 誤差。このPIP数以内であれば同じ値とする。            
      double bufDiff_PIPS       = NormalizeDouble(MathAbs(change_Point2PIPS(OpenTrade_OpenPrice[i] - n_mNewPrice)), global_Digits);

      // オープン中取引の建値と、発注予定価格よりENTRY_WIDTH_PIPS上の価格の誤差が許容範囲内なら、false
      // 又は
      // オープン中取引の建値と、発注予定価格よりENTRY_WIDTH_PIPS下の価格の誤差が許容範囲内なら、false
      if(bufDiff_PIPS <= allowableDiff_PIPS) {
printf( "[%d]COM2 未決済取引[%d] tick=%d の建値%sが、発注予定額%sとの差が%sであり、allowableDiff_PIPS=%s以下のため、実取引はしない" , __LINE__,
      i, 
      OpenTrade_Tick[i],
      DoubleToStr(n_bufOpenTrade_OpenPrice, global_Digits),  // 未決済取引の建値
      DoubleToStr(n_mNewPrice, global_Digits),               // 発注予定額    
      DoubleToStr(bufDiff_PIPS, global_Digits),
      DoubleToStr(allowableDiff_PIPS, global_Digits)
);
         return false;
      }
   }

   return true;
}
*/

// 引数のマジックナンバーで、ロング又はショートを、mNewPriceで発注できれば、true。それ以外は、false
// 1) 発注予定価格mNewPriceが、取引可能な価格の範囲であること
// 省略中2) 発注予定価格mNewPrice±mEntryWdth_PIPSの範囲内にと同じ売買種別の取引があれば、false
bool is_TradablePrice(int magic,               // マジックナンバー
                      int mBuySell,            // 売買区分
                      double mTradableMax,     // 取引可能上限（グローバル変数のg_long_Maxなど）
                      double mTradableMin,     // 取引可能下限（グローバル変数のg_long_Minなど）                      
                      double mEntryWdth_PIPS,  // 何PIPSの間隔を空けるのか
                      double mNewPrice) {      // 発注しようとしている価格
   double n_mTradableMax    = NormalizeDouble(mTradableMax, global_Digits); 
   double n_mTradableMin    = NormalizeDouble(mTradableMin, global_Digits);
   double n_mEntryWdth_PIPS = NormalizeDouble(mEntryWdth_PIPS, global_Digits);
   double n_mNewPrice       = NormalizeDouble(mNewPrice, global_Digits);

   // 1) 発注予定価格mNewPriceが、取引可能な価格の範囲であること
   if(n_mNewPrice > n_mTradableMax || n_mNewPrice < n_mTradableMin) {
/*   
if(mBuySell == SELL_SIGNAL) {   
printf( "[%d]PB 売りシグナル　is_TradablePriceで否定  mNewPrice=%s n_mTradableMax=%s  n_mTradableMin=%s " , __LINE__, 
DoubleToStr(mNewPrice, global_Digits),
DoubleToStr(n_mTradableMax, global_Digits),
DoubleToStr(n_mTradableMin, global_Digits)

);
}*/
      return false;
      
   }
   

   return true;
}

/*
// この条件を省略する前→2) 発注予定価格mNewPrice±mEntryWdth_PIPSの範囲内にと同じ売買種別の取引があれば、false
bool org_is_TradablePrice(int magic,               // マジックナンバー
                      int mBuySell,            // 売買区分
                      double mTradableMax,     // 取引可能上限（グローバル変数のg_long_Maxなど）
                      double mTradableMin,     // 取引可能下限（グローバル変数のg_long_Minなど）                      
                      double mEntryWdth_PIPS,  // 何PIPSの間隔を空けるのか
                      double mNewPrice) {      // 発注しようとしている価格
   double n_mTradableMax    = NormalizeDouble(mTradableMax, global_Digits); 
   double n_mTradableMin    = NormalizeDouble(mTradableMin, global_Digits);
   double n_mEntryWdth_PIPS = NormalizeDouble(mEntryWdth_PIPS, global_Digits);
   double n_mNewPrice       = NormalizeDouble(mNewPrice, global_Digits);

   // 1) 発注予定価格mNewPriceが、取引可能な価格の範囲であること
   if(n_mNewPrice > n_mTradableMax || n_mNewPrice < n_mTradableMin) {
      return false;
   }
   
   
   int i;

   double n_bufOpenTrade_OpenPrice; // OpenTrade_OpenPrice[i] をNormalizeDouble化した値段
printf( "[%d]COM read_OpenTrades実行" , __LINE__);   
   
read_OpenTrades(magic);

   // 2) 発注予定価格mNewPrice±mEntryWdth_PIPSの範囲内にと同じ売買種別の取引があれば、false
   for(i = 0; i < MAX_TRADE_NUM; i++) {
      // メモリ上のオープン取引が異常な値の時は、処理を終了する。
      if(OpenTrade_BuySell[i] <= INT_MIN
         || (OpenTrade_BuySell[i] != OP_SELL && OpenTrade_BuySell[i] != OP_BUY)) {
         break;
      }
      // メモリ上のオープン取引の売買タイプが、引数mBuySellと異なれば、次のデータに処理を移す。。
      if(OpenTrade_BuySell[i] != mBuySell) {
         continue;
      }
      
      // オープン中取引の値
      n_bufOpenTrade_OpenPrice = NormalizeDouble(OpenTrade_OpenPrice[i], global_Digits); 

      // 誤差
      double bufDiff = NormalizeDouble(MathAbs(OpenTrade_OpenPrice[i] - n_mNewPrice) / global_Points, global_Digits);

      // オープン中取引の建値と、発注予定価格よりENTRY_WIDTH_PIPS上の価格の誤差が許容範囲内なら、false
      // 又は
      // オープン中取引の建値と、発注予定価格よりENTRY_WIDTH_PIPS下の価格の誤差が許容範囲内なら、false
      if(bufDiff <= mEntryWdth_PIPS) {
printf( "[%d]COM2 未決済取引[%d] tick=%d の建値%sが、発注予定額%sとの差が%sであり、mEntryWdth_PIPS=%s以下のため、実取引はしない" , __LINE__,
      i, 
      OpenTrade_Tick[i],
      DoubleToStr(n_bufOpenTrade_OpenPrice, global_Digits),  // 未決済取引の建値
      DoubleToStr(n_mNewPrice, global_Digits),               // 発注予定額    
      DoubleToStr(bufDiff, global_Digits),
      DoubleToStr(mEntryWdth_PIPS, global_Digits)
);
         return false;
      }
   }

   return true;
}
*/

// オープン中の取引を取得する。
// 取得した取引件数を返す。
int read_OpenTrades(int magic) {
   int i;
   
   // グローバル変数の初期化
   ArrayInitialize(OpenTrade_BuySell, INT_MIN);
   ArrayInitialize(OpenTrade_OpenPrice, DOUBLE_VALUE_MIN);
   ArrayInitialize(OpenTrade_Tick, INT_MIN);
   
   int buysell = INT_MIN;
   int numOpenTrade = 0;
   for(i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
         // 未決済の取引をマジックナンバーで抽出する。
         if(OrderMagicNumber() == magic && OrderCloseTime() <= 0.0) {
            buysell = OrderType();
            if(buysell == OP_SELL || buysell == OP_BUY) {
               OpenTrade_BuySell[numOpenTrade]   = buysell;
               OpenTrade_OpenPrice[numOpenTrade] = OrderOpenPrice();
               OpenTrade_Tick[numOpenTrade] = OrderTicket();
               numOpenTrade++;
            }
         }
      }
   }
   return numOpenTrade;
}



// 数値を特定の長さになるまで先頭に0を付け足すための関数。
// 例えば4桁でゼロパディングする場合、123であれば0123、15であれば0015に修正する。
string ZeroPadding(int value, int digits){
   string result = IntegerToString(value);
   int    length = StringLen(result);

   if(length >= digits){
      return(result);
   }
   
   for(int i = 0; i < digits - length; i++){
      result = "0" + result;
   }
   
   return(result);
}



void MyObjectsDeleteAll() {
   ObjectDelete("PGName");
   ObjectDelete("Long_Max");
   ObjectDelete("Long_Min");
   ObjectDelete("Short_Max");
   ObjectDelete("Short_Min");
}


/*20221227
// 取引しようとしている価格が、トレードラインの買い又は売り可能な範囲内にあれば、trueを返す。それ以外は、falseを返す。
// 必要な外部パラメータ
// - ENTRY_WIDTH_PIPS
// - ALLOWABLE_DIFF_PER
bool judge_Tradable_Price(int    mMagic,   // マジックナンバー
                          int    mBuySell, // BUY_SIGNAL, SELL_SIGNAL
                          double mPrice    // 取引しようとしている価格
                          ) {
   double   past_max;     // 過去の最高値
   datetime past_maxTime; // 過去の最高値の時間
   double   past_min;     // 過去の最安値
   datetime past_minTime; // 過去の最安値の時間
   double   past_width;   // 過去値幅。past_max - past_min
   double   long_Min;     // ロング取引を許可する最小値
   double   long_Max;     // ロング取引を許可する最大値
   double   short_Min;    // ショート取引を許可する最小値
   double   short_Max;    // ショート取引を許可する最大値
   bool flag_read_TradingLines = read_TradingLines(past_max,  // 出力：過去の最高値
                                              past_maxTime,   // 出力：過去の最高値の時間
                                              past_min,       // 出力：過去の最安値
                                              past_minTime,   // 出力：過去の最安値の時間
                                              past_width,     // 出力：過去値幅。past_max - past_min
                                              long_Min,       // 出力：ロング取引を許可する最小値
                                              long_Max,       // 出力：ロング取引を許可する最大値
                                              short_Min,      // 出力：ショート取引を許可する最小値
                                              short_Max       // 出力：ショート取引を許可する最大値
                                            );
                          
   if(flag_read_TradingLines == false) {
      return false;
   }
   double allawableDiff_PIPS = NormalizeDouble(ENTRY_WIDTH_PIPS * ALLOWABLE_DIFF_PER / 100.0, global_Digits); // 許容誤差。PIPS単位。
   bool   flagRet = false;

   if(mBuySell == BUY_SIGNAL) {
      flagRet = is_TradablePrice(mMagic,             // マジックナンバー
                                 BUY_SIGNAL,         // 売買区分
                                 long_Max,         // 取引可能上限（グローバル変数のg_long_Maxなど）
                                 long_Min,         // 取引可能下限（グローバル変数のg_long_Minなど）
                                 allawableDiff_PIPS, // 何PIPSの誤差を許容するのか
                                 mPrice);            // 発注しようとしている価格
   }
   else if(mBuySell == SELL_SIGNAL) {
      flagRet = is_TradablePrice(mMagic,             // マジックナンバー
                                 SELL_SIGNAL,        // 売買区分
                                 short_Max,         // 取引可能上限（グローバル変数のg_long_Maxなど）
                                 short_Min,         // 取引可能下限（グローバル変数のg_long_Minなど）
                                 allawableDiff_PIPS, // 何PIPSの誤差を許容するのか
                                 mPrice);            // 発注しようとしている価格

   }
   
   return flagRet;
}

*/

bool get_TPSL_FromComment(string mComment,  // 入力。コメント文字列 
                          double &mTPValue, // 出力：<T～/T>を数値化。失敗時は、-1。
                          double &mSLValue  // 出力：<S～/S>を数値化。失敗時は、-1。
                         ) {
   mTPValue = -1;
   mSLValue = -1;
   string TP_Header = "<T";
   string TP_Footer = "/T>";
   string SL_Header = "<S";
   string SL_Footer = "/S>";

   int index_TP_Header = StringFind(mComment, TP_Header);
   int index_TP_Footer = StringFind(mComment, TP_Footer);
   int index_SL_Header = StringFind(mComment, SL_Header);
   int index_SL_Footer = StringFind(mComment, SL_Footer);


   if( (index_TP_Header  < 0 || index_TP_Footer < 0) 
        && (index_SL_Header  < 0 || index_SL_Footer < 0) ) {
      
      return false;
   }
   string bufTP = "";
   string bufSL;
   if(index_TP_Header  < 0 || index_TP_Footer < 0) {
      mTPValue = -1;
   }
   else {
      int index_TPValuse_Header = index_TP_Header + StringLen(TP_Header);
      int index_TPValuse_Footer = index_TP_Footer - 1;
      if(index_TPValuse_Header <= index_TPValuse_Footer) {
         bufTP = StringSubstr(mComment, index_TPValuse_Header, index_TPValuse_Footer);
         mTPValue = StringToDouble(bufTP);
      }
      else {
//         printf( "[%d]PB TP取得失敗" , __LINE__);
         mTPValue = -1;
      }
   }
   if(index_SL_Header  < 0 || index_SL_Footer < 0) {
      mSLValue = -1;
   }
   else {
      int index_SLValuse_Header = index_SL_Header + StringLen(SL_Header);
      int index_SLValuse_Footer = index_SL_Footer - 1;
      if(index_SLValuse_Header <= index_SLValuse_Footer) {
         bufSL = StringSubstr(mComment, index_SLValuse_Header, index_SLValuse_Footer);
         mSLValue = StringToDouble(bufSL);
      }
      else {
//         printf( "[%d]PB SL取得失敗" , __LINE__);
         mSLValue = -1;
      }
   }

    return true;
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
/*printf( "[%d]COM ピンバー判断対象>%s<　Open=%s High=%s Low=%s Close=%s" , __LINE__, TimeToStr(iTime(global_Symbol, mTimeFrame, mShift)), 
DoubleToStr(open_i, 8),
DoubleToStr(high_i, 8),
DoubleToStr(low_i, 8),
DoubleToStr(close_i, 8));*/

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
   if(down_div >= 0.0
      && up_div > down_div) {
      // 実体の長さが、上髭のmPinBarPIN_MAX_PER％未満ならピン
      body_Size = MathAbs(open_i - close_i);  // 実体の長さ
      if(body_Size / up_div * 100.0 < mPinBarPIN_MAX_PER) {
         // 上髭ピンが見つかった
         if(mSignal == BUY_SIGNAL) {  // 下髭ピンを探そうとしていたのでfalseを返す。
            return false;
         }
         else {
/*printf( "[%d]COM 上髭発見>%s<　実体=%s ÷ 上ヒゲ=%s = %s < %s" , __LINE__, TimeToStr(iTime(global_Symbol, mTimeFrame, mShift)), 
         DoubleToString(body_Size, global_Digits),
         DoubleToString(up_div, global_Digits),
         DoubleToString(body_Size / up_div * 100.0, global_Digits),
         DoubleToString(mPinBarPIN_MAX_PER, global_Digits)
         );      */
/*printf( "[%d]COM 上髭を描画するためのパラメータ　　時刻=>%s<　値段%s" , __LINE__, TimeToStr(iTime(global_Symbol, mTimeFrame, mShift)), 
         TimeToStr(iTime(global_Symbol, mTimeFrame, mShift)),
         DoubleToStr(iHigh(global_Symbol, mTimeFrame, mShift) , 8) );*/
         CreateArrawObject(OBJ_ARROW_SELL,                             //オブジェクトの種類(OBJ_ARROW_BUY/OBJ_ARROW_SELL)
                           iTime(global_Symbol, mTimeFrame, mShift),   //表示時間（横軸）
                           iHigh(global_Symbol, mTimeFrame, mShift) ); //表示時間（縦軸）
            return true;
         }
      }
   }
   //　下髭が長い場合
   else if(down_div > 0.0 
      && up_div < down_div) {
      // 実体の長さが、下髭のmPinBarPIN_MAX_PER％未満ならピン
      body_Size = MathAbs(open_i - close_i);
      if(body_Size / down_div * 100.0 < mPinBarPIN_MAX_PER) {
//printf( "[%d]COM 下髭発見>%s<" , __LINE__, TimeToStr(iTime(global_Symbol, mTimeFrame, mShift)));
         CreateArrawObject(OBJ_ARROW_BUY,                             //オブジェクトの種類(OBJ_ARROW_BUY/OBJ_ARROW_SELL)
                           iTime(global_Symbol, mTimeFrame, mShift),   //表示時間（横軸）
                           iLow(global_Symbol, mTimeFrame, mShift) ); //表示時間（縦軸）
      
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



datetime Mount_TimeDate[100];
datetime Valley_TimeDate[100];
double   Mount_Price[100];
double   Valley_Price[100];

bool get_MountValley(int mEndShift, // 何シフト前まで検索するか
                    datetime &mMount_TimeDate[], // 山が発生したと判断されるシフトの日付
                    double   &mMount_Price[],                    
                    datetime &mValley_TimeDate[], // 谷が発生したと判断されるシフトの日付
                    double   &mValley_Price[]
               ) {
   // 終了シフトが2未満の時は計算できないため、falseを返す。
   if(mEndShift < 2) {
      return false;
   }

   // 山、谷の日付を保存する配列を0で初期化する。
   ArrayInitialize(mMount_TimeDate, 0);
   ArrayInitialize(mValley_TimeDate, 0);

   int i;
   bool flag_is_Pinbar = false;

   double localOpen[1000];  // i番目のOpen値を格納する。
   double localHigh[1000];  // i番目のHigh値を格納する。
   double localLow[1000];   // i番目のLow値を格納する。
   double localClose[1000]; // i番目のClose値を格納する。
   // 4値を保存する配列を0で初期化する。
   ArrayInitialize(localOpen, 0.0);
   ArrayInitialize(localHigh, 0.0);
   ArrayInitialize(localLow, 0.0);
   ArrayInitialize(localClose, 0.0);

   double localBodyHigh[1000];  // i番目の実線高値
   double localBodyLow[1000];   // i番目の実線安値

   int    mountNum = 0; // 何番目の山か。
   int    valleyNum = 0; // 何番目の谷か。

   for(i = 2; i <= mEndShift; i++) {
      bool flag_Mount  = true; // 山の条件を満たさない項目があれば、falseに変わる
      bool flag_Valley = true; // 谷の条件を満たさない項目があれば、falseに変わる

      //
      //シフトiが上ヒゲであること
      //
      flag_is_Pinbar = is_PinBar(0,           // 計算用時間軸
                                 SELL_SIGNAL, // 下髭のPinBARを探す時は、BUY_SIGNAL。上髭を探す時は、SELL_SIGNAL
                                 i,           // 何本前のシフトがPinBarを形成しているか
                                 50);         // 実体部分(始値と終値の差）が最高値と最安値の何％以下ならPinBARとみなすか
      if(flag_is_Pinbar == true) {
         //
         // シフト(i + 1)の実線高値が、シフトiの実線高値より低いこと
         //
         if(localClose[i] <= 0.0) {  // ループの途中でシフトiの値を取得していれば、再取得はしない。
            localClose[i]   = iClose(global_Symbol, 0, i);
            localOpen[i]    = iOpen(global_Symbol, 0, i);
         }
         if(localOpen[i + 1] <= 0.0) { // ループの途中でシフト(i + 1)の値を取得していれば、再取得はしない。
            localOpen[i + 1]  = iOpen(global_Symbol, 0, i + 1);
            localClose[i + 1] = iClose(global_Symbol, 0, i + 1);
         }
   
         // 現時点の実線高値を計算する。
         if(localOpen[i] > localClose[i]) { 
            localBodyHigh[i] = localOpen[i];
         }
         else {
            localBodyHigh[i] = localClose[i];
         }
    
         // シフト(i + 1)の実線高値を計算する。
         if(localOpen[i+1] > localClose[i+1]) { 
            localBodyHigh[i+1] = localOpen[i+1];
         }
         else {
            localBodyHigh[i+1] = localClose[i+1];
         }

         // シフト(i + 1)の実線高値が、シフトiの実線高値より低いので次へ
         if(localBodyHigh[i+1] < localBodyHigh[i]) {
            //
            // シフト(i + 2)の実線高値が、シフト(i + 1)の実線高値より低いこと
            //

            // シフト(i + 2)の実線高値を計算する。
            if(localOpen[i + 2] <= 0.0) { // ループの途中でシフト(i + 2)の値を取得していれば、再取得はしない。
               localOpen[i + 2]  = iOpen(global_Symbol, 0, i + 2);
               localClose[i + 2] = iClose(global_Symbol, 0, i + 2);
            }
            // シフト(i + 2)の実線高値を計算する。
            if(localOpen[i + 2] > localClose[i + 2]) { 
               localBodyHigh[i + 2] = localOpen[i + 2];
            }
            else {
               localBodyHigh[i + 2] = localClose[i + 2];
            }


            // シフト(i + 2)の実線高値が、シフト(i + 1)の実線高値より低いので次へ
            if(localBodyHigh[i + 2] < localBodyHigh[i + 1]) {
               //
               // シフト(i - 1)の実線高値が、シフトiの実線高値より低いこと
               // 

               // シフト(i - 1)の実線高値を計算する。
               if(localOpen[i - 1] <= 0.0) { // ループの途中でシフト(i - 1)の値を取得していれば、再取得はしない。
                  localOpen[i - 1]  = iOpen(global_Symbol, 0, i - 1);
                  localClose[i - 1] = iClose(global_Symbol, 0, i - 1);
               }
               // シフト(i - 1)の実線高値を計算する。
               if(localOpen[i - 1] > localClose[i - 1]) { 
                  localBodyHigh[i - 1] = localOpen[i - 1];
               }
               else {
                  localBodyHigh[i - 1] = localClose[i - 1];
               }
               // シフト(i - 1)の実線高値が、シフト(i)の実線高値より低いので次へ
               if(localBodyHigh[i - 1] < localBodyHigh[i]) {
                  //
                  // シフト(i - 2)の実線高値が、シフト(i - 1)の実線高値より低いこと
                  // 
 
                  // シフト(i - 2)の実線高値を計算する。
                  if(localOpen[i - 2] <= 0.0) { // ループの途中でシフト(i - 2)の値を取得していれば、再取得はしない。
                     localOpen[i - 2]  = iOpen(global_Symbol, 0, i - 2);
                     localClose[i - 2] = iClose(global_Symbol, 0, i - 2);
                  }
                  // シフト(i - 2)の実線高値を計算する。
                  if(localOpen[i - 2] > localClose[i - 2]) { 
                     localBodyHigh[i - 2] = localOpen[i - 2];
                  }
                  else {
                     localBodyHigh[i - 2] = localClose[i - 2];
                  }
                  // シフト(i - 2)の実線高値が、シフト(i - 1)の実線高値より低いので、シフトiは山確定
                  if(localBodyHigh[i - 2] < localBodyHigh[i - 1]) {
                     mMount_TimeDate[mountNum] = iTime(global_Symbol, 0, i);
                     mMount_Price[mountNum] = iHigh(global_Symbol, 0, i);
                     mountNum = mountNum + 1;
                  }
                  else {
                     flag_Mount  = false;
                  }
                  
               }
               // シフト(i - 1)の実線高値が、シフト(i)の実線高値より高い時は、シフトiは、少なくとも山ではない。
               else {
                  flag_Mount  = false;
               }



            }

            // シフト(i + 2)の実線高値が、シフト(i + 1)の実線高値より高い時は、シフトiは、少なくとも山ではない。
            else {
               flag_Mount  = false;
            }
         }
         // シフト(i + 1)の実線高値がシフトiの実線高値より高い時は、シフトiは、少なくとも山ではない。
         else {
            flag_Mount  = false;
         }
      }
      // 上髭でなければ、シフトiは、少なくとも山ではない。
      else {
         flag_Mount  = false;
      }



      //
      //シフトiが下ヒゲであること
      //
      flag_is_Pinbar = is_PinBar(0,           // 計算用時間軸
                                 BUY_SIGNAL, // 下髭のPinBARを探す時は、BUY_SIGNAL。上髭を探す時は、SELL_SIGNAL
                                 i,           // 何本前のシフトがPinBarを形成しているか
                                 50);         // 実体部分(始値と終値の差）が最高値と最安値の何％以下ならPinBARとみなすか
      if(flag_is_Pinbar == true) {
         //
         // シフト(i + 1)の実線安値が、シフトiの実線安値より高いこと
         //
         if(localClose[i] <= 0.0) {  // ループの途中でシフトiの値を取得していれば、再取得はしない。
            localClose[i]   = iClose(global_Symbol, 0, i);
            localOpen[i]    = iOpen(global_Symbol, 0, i);
         }
         if(localOpen[i + 1] <= 0.0) { // ループの途中でシフト(i + 1)の値を取得していれば、再取得はしない。
            localOpen[i + 1]  = iOpen(global_Symbol, 0, i + 1);
            localClose[i + 1] = iClose(global_Symbol, 0, i + 1);
         }
   
         // 現時点の実線安値を計算する。
         if(localOpen[i] < localClose[i]) { 
            localBodyHigh[i] = localOpen[i];
         }
         else {
            localBodyHigh[i] = localClose[i];
         }
    
         // シフト(i + 1)の実線安値を計算する。
         if(localOpen[i + 1] < localClose[i + 1]) { 
            localBodyHigh[i + 1] = localOpen[i + 1];
         }
         else {
            localBodyHigh[i + 1] = localClose[i + 1];
         }

         // シフト(i + 1)の実線安値が、シフトiの実線高値より高いので次へ
         if(localBodyHigh[i + 1] > localBodyHigh[i]) {
            //
            // シフト(i + 2)の実線安値が、シフト(i + 1)の実線安値より高いこと
            //

            // シフト(i + 2)の実線安値を計算する。
            if(localOpen[i + 2] <= 0.0) { // ループの途中でシフト(i + 2)の値を取得していれば、再取得はしない。
               localOpen[i + 2]  = iOpen(global_Symbol, 0, i + 2);
               localClose[i + 2] = iClose(global_Symbol, 0, i + 2);
            }
            // シフト(i + 2)の実線安値を計算する。
            if(localOpen[i + 2] < localClose[i + 2]) { 
               localBodyHigh[i + 2] = localOpen[i + 2];
            }
            else {
               localBodyHigh[i + 2] = localClose[i + 2];
            }


            // シフト(i + 2)の実線安値が、シフト(i + 1)の実線安値より高いので次へ
            if(localBodyHigh[i + 2] > localBodyHigh[i + 1]) {
               //
               // シフト(i - 1)の実線安値が、シフトiの実線安値より高いこと
               // 

               // シフト(i - 1)の実線安値を計算する。
               if(localOpen[i - 1] <= 0.0) { // ループの途中でシフト(i - 1)の値を取得していれば、再取得はしない。
                  localOpen[i - 1]  = iOpen(global_Symbol, 0, i - 1);
                  localClose[i - 1] = iClose(global_Symbol, 0, i - 1);
               }
               // シフト(i - 1)の実線安値を計算する。
               if(localOpen[i - 1] < localClose[i - 1]) { 
                  localBodyHigh[i - 1] = localOpen[i - 1];
               }
               else {
                  localBodyHigh[i - 1] = localClose[i - 1];
               }
               // シフト(i - 1)の実線安値が、シフト(i)の実線安値より高いので次へ
               if(localBodyHigh[i - 1] > localBodyHigh[i]) {
                  //
                  // シフト(i - 2)の実線高値が、シフト(i - 1)の実線高値より高いこと
                  // 
 
                  // シフト(i - 2)の実線高値を計算する。
                  if(localOpen[i - 2] <= 0.0) { // ループの途中でシフト(i - 2)の値を取得していれば、再取得はしない。
                     localOpen[i - 2]  = iOpen(global_Symbol, 0, i - 2);
                     localClose[i - 2] = iClose(global_Symbol, 0, i - 2);
                  }
                  // シフト(i - 2)の実線高値を計算する。
                  if(localOpen[i - 2] > localClose[i - 2]) { 
                     localBodyHigh[i - 2] = localOpen[i - 2];
                  }
                  else {
                     localBodyHigh[i - 2] = localClose[i - 2];
                  }
                  // シフト(i - 2)の実線高値が、シフト(i - 1)の実線高値より高いので、シフトiは谷確定
                  if(localBodyHigh[i - 2] > localBodyHigh[i - 1]) {
                     mValley_TimeDate[valleyNum] = iTime(global_Symbol, 0, i);
                     mValley_Price[valleyNum] = iLow(global_Symbol, 0, i);
                     valleyNum = valleyNum + 1;
                  }
                  else {
                     flag_Valley  = false;
                  }
                  
               }
               // シフト(i - 1)の実線高値が、シフト(i)の実線高値より高い時は、シフトiは、少なくとも山ではない。
               else {
                  flag_Valley  = false;
               }
            }

            // シフト(i + 2)の実線高値が、シフト(i + 1)の実線高値より高い時は、シフトiは、少なくとも山ではない。
            else {
               flag_Mount  = false;
            }
         }
         // シフト(i + 1)の実線高値がシフトiの実線高値より高い時は、シフトiは、少なくとも山ではない。
         else {
            flag_Mount  = false;
         }
      }
      // 下髭でなければ、シフトiは、少なくとも谷ではない。
      else {
         flag_Valley  = false;
      }
   }   //    for(i = 2; i <= mEndShift; i++) {
   return true;
}




void draw_MountValley_Lines() {
   int i;
   bool valueFlag = true;  // 描画するためのデータが、最初の3点で不正（時刻データが0）であれば、falseとする。

   for(i = 0; i < 3; i++) {
      if(Mount_TimeDate[i] <= 0) {
         valueFlag = false;
         break;
      }
      if(Valley_TimeDate[i] <= 0) {
         valueFlag = false;
         break;
      }
   }

   ObjectCreate("FirstLine", OBJ_TREND, 0, 0, 0);
   ObjectCreate("SecondLine", OBJ_TREND, 0, 0, 0);
   if(valueFlag == true) {
      ObjectDelete("FirstLine");
      // 最新が山の時は、山の0、谷の0、山の1、谷の1の順に線を引く
      if(Mount_TimeDate[0] > Valley_TimeDate[0]) {
printf( "[%d]PB　山　→　谷　→　山" , __LINE__);      
         ObjectCreate("FirstLine", OBJ_TREND,0, Mount_TimeDate[0], Mount_Price[0], Valley_TimeDate[0],  Valley_Price[0]);
         ObjectSet("FirstLine",OBJPROP_COLOR, clrYellow);
         ObjectSet("FirstLine",OBJPROP_WIDTH,3);
         ObjectSet("FirstLine", OBJPROP_STYLE, STYLE_DOT);

         ObjectCreate("SecondLine", OBJ_TREND,0, Valley_TimeDate[0],  Valley_Price[0], Mount_TimeDate[1], Mount_Price[1]);
         ObjectSet("SecondLine",OBJPROP_COLOR, clrYellow);
         ObjectSet("SecondLine",OBJPROP_WIDTH,3);
         ObjectSet("SecondLine", OBJPROP_STYLE, STYLE_DOT);  
      }
      else if(Mount_TimeDate[0] < Valley_TimeDate[0]) {
printf( "[%d]PB　谷　→　山　→　谷" , __LINE__);            
         ObjectCreate("FirstLine", OBJ_TREND,0, Valley_TimeDate[0],  Valley_Price[0],  Mount_TimeDate[0],  Mount_Price[0]);
         ObjectSet("FirstLine",OBJPROP_COLOR, clrYellow);
         ObjectSet("FirstLine",OBJPROP_WIDTH,3);
         ObjectSet("FirstLine", OBJPROP_STYLE, STYLE_DOT);

         ObjectCreate("SecondLine", OBJ_TREND,0, Mount_TimeDate[0],  Mount_Price[0], Valley_TimeDate[1],  Valley_Price[1]);
         ObjectSet("SecondLine",OBJPROP_COLOR, clrYellow);
         ObjectSet("SecondLine",OBJPROP_WIDTH,3);
         ObjectSet("SecondLine", OBJPROP_STYLE, STYLE_DOT);

      }

   }
}


/* ------------------------------------------------------------------
 * 実効レバレッジ計算
 * ------------------------------------------------------------------ */
// 実効レバレッジ = 取引総額 ÷ 有効証拠金
// 取引総額 ≒ 取引証拠金総額 × 口座のレバレッジ
double GetRoughEffectiveLeverage() {
   double ret = NormalizeDouble(AccountMargin(), global_Digits) * NormalizeDouble(GetTrueAccountLeverage(), global_Digits) / NormalizeDouble(AccountEquity(), global_Digits);
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



// 余剰証拠金維持率
double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

// 余剰証拠金
double  account_freemargin = AccountFreeMargin();

//SO_SO は強制ロスカットになるレベル
double so_so   = AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);

// 強制ロスカットのレベルは業者によって、
// 割合（余剰証拠金維持率）：ACCOUNT_MARGIN_SO_MODEが、ACCOUNT_STOPOUT_MODE_PERCENT
// 金額（余剰証拠金）　　　：ACCOUNT_MARGIN_SO_MODEが、ACCOUNT_STOPOUT_MODE_MONEY

ENUM_ACCOUNT_STOPOUT_MODE stop_mode = (ENUM_ACCOUNT_STOPOUT_MODE) AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
// 0: ACCOUNT_STOPOUT_MODE_PERCENT
// 1: ACCOUNT_STOPOUT_MODE_MONEY


bool get_MarginlevelRateOrFreeMarginMoney(double &mMargin_level,      // 出力：余剰証拠金維持率。業者が使用しなければ、-1
                                          double &mAccount_freemargin // 出力：余剰証拠金。業者が使用しなければ、-1
                                          ) {
   ////////////////////////////////////////////////////////////////////////////////////////
   // 余剰証拠金維持率
   // double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   // 
   // 余剰証拠金
   // double  account_freemargin = AccountFreeMargin();
   //
   //SO_SO は強制ロスカットになるレベル
   // double so_so   = AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
   // 
   // 強制ロスカットのレベルは業者によって、
   //    割合（余剰証拠金維持率）：ACCOUNT_MARGIN_SO_MODEが、ACCOUNT_STOPOUT_MODE_PERCENT
   //    金額（余剰証拠金）　　　：ACCOUNT_MARGIN_SO_MODEが、ACCOUNT_STOPOUT_MODE_MONEY
   ////////////////////////////////////////////////////////////////////////////////////////

   ENUM_ACCOUNT_STOPOUT_MODE mStop_mode = (ENUM_ACCOUNT_STOPOUT_MODE) AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);
   // 0: ACCOUNT_STOPOUT_MODE_PERCENT
   // 1: ACCOUNT_STOPOUT_MODE_MONEY
   if(mStop_mode == ACCOUNT_STOPOUT_MODE_PERCENT) {
      mMargin_level       = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), global_Digits);
      mAccount_freemargin = -1.0;
   }
   else if(mStop_mode == ACCOUNT_STOPOUT_MODE_MONEY) {
      mMargin_level       = -1;
      mAccount_freemargin = AccountFreeMargin();
   }
   else {
      mMargin_level       = -1;
      mAccount_freemargin = -1;
      return false;
   }
   return true;
}

//矢印オブジェクトを生成する。
bool CreateArrawObject(
   ENUM_OBJECT objectType,  //オブジェクトの種類(OBJ_ARROW_BUY/OBJ_ARROW_SELL)
   datetime time,           //表示時間（横軸）
   double price )           //表示時間（縦軸）
{
   // ラベルオフセット
   double labelOffset = 0;

   // 表示小数点
   int marketDigit = 8;
   
   //オブジェクトを作成する。
   long chartId = ChartID();

   string objectName = StringFormat("%s_ARR_%s_%s", OBJECT_NAME, objectType == OBJ_ARROW_BUY ? "B" : "S", TimeToStr(time));
   
   if( !ObjectCreate(chartId, objectName, objectType, 0, time, price) )
   {
      return false;
   }

   // 読み取り専用
   ObjectSetInteger(0, objectName, OBJPROP_READONLY, true);
   // 選択不可
   ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
   // 名前を隠す
   ObjectSetInteger(chartId, OBJECT_NAME, OBJPROP_HIDDEN, true);
   // アンカー
   ObjectSetInteger(chartId, objectName, OBJPROP_ANCHOR, objectType == OBJ_ARROW_BUY ? ANCHOR_BOTTOM : ANCHOR_TOP);
   // 色
   ObjectSetInteger(chartId, objectName, OBJPROP_COLOR, objectType == OBJ_ARROW_BUY ? C'200,200,255' : C'255,128,128');
   // ↑種別
   ObjectSetInteger(chartId, objectName, OBJPROP_ARROWCODE, objectType == OBJ_ARROW_BUY ? 233 : 234);
   
   //価格テキストを追加する。
   objectName = StringFormat("%s_TXT_%s_%s", OBJECT_NAME, objectType == OBJ_ARROW_BUY ? "B" : "S", TimeToStr(time));

   // 表示位置を矢印の大きさの分だけ上方向にずらす。
   price = price + labelOffset * (objectType == OBJ_ARROW_BUY ? 1 : -1);

   if( !ObjectCreate(chartId, objectName, OBJ_TEXT, 0, time, price) )
   {
      return false;
   }

   // 読み取り専用
   ObjectSetInteger(0, objectName, OBJPROP_READONLY, true);
   // 選択不可
   ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
   // 名前を隠す
   ObjectSetInteger(chartId, OBJECT_NAME, OBJPROP_HIDDEN, true);
   // アンカー
   ObjectSetInteger(chartId, objectName, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
   // 色
   ObjectSetInteger(chartId, objectName, OBJPROP_COLOR, objectType == OBJ_ARROW_BUY ? C'200,200,255' : C'255,128,128');
   // 角度 縦に回転させる。
   ObjectSetDouble(chartId, objectName, OBJPROP_ANGLE, objectType == OBJ_ARROW_BUY ? 90 : -90);

   // 表示文字列
   ObjectSetString(chartId, objectName, OBJPROP_TEXT, DoubleToString(price, marketDigit));

   return true;
}
//UPDOWN サインオブジェクト名
const string OBJECT_NAME = "OjbectSign";
//売買矢印オブジェクトを生成する。
bool orgCreateArrawObject(
   ENUM_OBJECT objectType,  //オブジェクトの種類(OBJ_ARROW_BUY/OBJ_ARROW_SELL)
   datetime time,           //表示時間（横軸）
   double price )           //表示時間（縦軸）
{
   //オブジェクトを作成する。
   long chartId = ChartID();

//   ObjectDelete(chartId, OBJECT_NAME);

   if( !ObjectCreate(chartId, OBJECT_NAME, objectType, 0, time, price) )
   {
      return false;
   }
   ObjectSetInteger(chartId, OBJECT_NAME, OBJPROP_HIDDEN, true);
   ObjectSetInteger(chartId, OBJECT_NAME, OBJPROP_COLOR, objectType == OBJ_ARROW_BUY ? C'200,200,255' : C'255,128,128');
   ObjectSetInteger(chartId, OBJECT_NAME, OBJPROP_ARROWCODE, objectType == OBJ_ARROW_BUY ? 233 : 234);

   return true;
}



// オープン中の取引件数を返す
// 引数のマジックナンバーは必須。
// 引数のmSymbol通貨ペアの長さが0の場合は、全ての通貨ペアの取引件数を返す。
int get_OpenTradeNum(ulong mMagic,  // マジックナンバー
                     string mSymbol // 通貨ペア
                    ) {
   if(mMagic <= 0) {
      return -1;
   }

   int retCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
         string orderSymbol      = OrderSymbol();
         long   orderMagicNumber = OrderMagicNumber();
         if( mMagic == orderMagicNumber  // マジックナンバーが一致するのは必須
                                         // 引数mSymbolの長さが0なら全通貨ペアがカウント対象。
                                         // 引数mSymbolの長さが正で一致すれば、カウント対象。
             && (StringLen(mSymbol) <= 0 || (StringLen(orderSymbol) > 0 && StringCompare(mSymbol, orderSymbol) == 0) ) ) {
            retCount = retCount + 1;
         }
      }
   }

   return retCount;
}

// オープン中の取引件数を返す
// 引数のマジックナンバーは必須。
int get_OpenTradeNum(ulong mMagic  // マジックナンバー
                    ) {
   if(mMagic <= 0) {
      return -1;
   }

   int retCount = 0;
   for(int i = OrdersTotal() - 1; i >= 0;i--) {
      if(OrderSelect(i,SELECT_BY_POS, MODE_TRADES) == true) { 
         long   orderMagicNumber = OrderMagicNumber();
         if(mMagic == orderMagicNumber) {  // マジックナンバーが一致するのは必須
        
            retCount = retCount + 1;
         }
      }
   }

   return retCount;
}





//+------------------------------------------------------------------+
//| 日本時間へ変換（夏時間・冬時間）
//| convertToJapanTime()
//|   とすれば現在のサーバ時間を日本時間で返す
//| convertToJapanTime(Time[n])
//|   などパラメータに指定時間を渡せば指定時間を日本時間に変換して返す
//+------------------------------------------------------------------+
datetime convertToJapanTime(datetime day = 0) {
   MqlDateTime cjtm; // 時間構造体
   day = day == 0 ? TimeCurrent() : day; // 対象サーバ時間
   datetime time_summer = 21600; // ６時間
   datetime time_winter = 25200; // ７時間
   int target_dow = 0; // 日曜日
   int start_st_n = 2; // 夏時間開始3月第2週
   int end_st_n = 1; // 夏時間終了11月第1週
   TimeToStruct(day, cjtm); // 構造体の変数に変換
   string year = (string)cjtm.year; // 対象年
   // 対象年の3月1日と11月1日の曜日
   TimeToStruct(StringToTime(year + ".03.01"), cjtm);
   int fdo_mar = cjtm.day_of_week;
   TimeToStruct(StringToTime(year + ".11.01"), cjtm);
   int fdo_nov = cjtm.day_of_week;
   // 3月第2日曜日
   int start_st_day = (target_dow < fdo_mar ? target_dow + 7 : target_dow)
                  - fdo_mar + 7 * start_st_n - 6;
   // 11月第1日曜日
   int end_st_day = (target_dow < fdo_nov ? target_dow + 7 : target_dow)
                - fdo_nov + 7 * end_st_n - 6;
   // 対象年の夏時間開始日と終了日を確定
   datetime start_st = StringToTime(year + ".03." + (string)start_st_day);
   datetime end_st = StringToTime(year + ".11." + (string)end_st_day);
   // 日本時間を返す
   return day += start_st <= day && day <= end_st
              ? time_summer : time_winter;
}


//+------------------------------------------------------------------+
//| EAをストップさせる条件を満たした時、trueを返す。
//+------------------------------------------------------------------+
bool stop_EA() {
   MqlDateTime timeStruct; // 時間構造体
   TimeToStruct(convertToJapanTime(0), timeStruct);

   // 朝5時から8時の間は、EAを停止させる。
   if(timeStruct.hour >= 5 && timeStruct.hour <= 8) {
      if(timeStruct.min == 0 && timeStruct.sec == 0) {
         printf( "[%d]COM 朝5時から8時の間は、EAを停止" , __LINE__);
      }
      return true;
   }

   // スプレッドが広い時は、EAを停止させる。
   double spread = MarketInfo(Symbol(), MODE_SPREAD); // 0.1pipsで1
   double stopSpread = 10.0;
   if(spread > stopSpread) {
         printf( "[%d]COM スプレッドが%s(> %s)のため、EAを停止" , __LINE__,
                  DoubleToString(spread, 8),
                  DoubleToString(stopSpread, 8)
                 );
      return true;
   }

   return false;
} 



void get_HighLowPrices(string   mSymbol,     // 通貨ペア
                       datetime mFromTime, // 開始時刻＝終了時刻より過去の時刻。
                       datetime mToTime,   // 終了時刻
                       double   &mHigh,    // 期間中の高値
                       double   &mLow      // 期間中の安値
                      ) {
   mHigh = DOUBLE_VALUE_MIN;
   mLow  = DOUBLE_VALUE_MIN;

   if(mFromTime > mToTime) {
      datetime buf = mToTime;
      mToTime   = mFromTime;
      mFromTime = mToTime;
   }
   int fromShift = iBarShift(mSymbol,PERIOD_M1,mFromTime); // 開始時刻を含むシフトを取得
   int toShift   = iBarShift(mSymbol,PERIOD_M1,mToTime);   // 終了時刻を含むシフトを取得
   int barCount  = fromShift - toShift + 1;

   mHigh = iHigh(mSymbol,PERIOD_M1,iHighest(mSymbol,PERIOD_M1,MODE_HIGH,barCount,toShift));
   mLow  = iLow(mSymbol,PERIOD_M1,iLowest(mSymbol,PERIOD_M1,MODE_LOW,barCount,toShift));
printf( "[%d]COM 開始時刻=>%s<  終了時刻=>%s<　高値=>%s<%s    安値=>%s<%s" , __LINE__,
         TimeToString(mFromTime),
         TimeToString(mToTime),
         DoubleToString(mHigh, 5),
         TimeToString(iTime(mSymbol,PERIOD_M1,fromShift)),
         DoubleToString(mLow,  5),
         TimeToString(iTime(mSymbol,PERIOD_M1,toShift))
      );
}

void get_4PricesByTime(string   mSymbol,   // 通貨ペア
                       datetime mFromTime, // 開始時刻＝終了時刻より過去の時刻。
                       datetime mToTime,   // 終了時刻
                       double   &mOpen,    // 期間中の始値
                       double   &mHigh,    // 期間中の高値
                       double   &mLow,     // 期間中の安値
                       double   &mClose    // 期間中の終値
                      ) {
   mOpen  = DOUBLE_VALUE_MIN;
   mHigh  = DOUBLE_VALUE_MIN;
   mLow   = DOUBLE_VALUE_MIN;
   mClose = DOUBLE_VALUE_MIN;

   if(mFromTime > mToTime) {
      datetime buf = mToTime;
      mToTime   = mFromTime;
      mFromTime = mToTime;
   }
   int fromShift = iBarShift(mSymbol,PERIOD_M1,mFromTime); // 開始時刻を含むシフトを取得
   int toShift   = iBarShift(mSymbol,PERIOD_M1,mToTime);   // 終了時刻を含むシフトを取得
   int barCount  = fromShift - toShift + 1;

   mOpen  = iOpen(mSymbol,PERIOD_M1,fromShift);
   mHigh  = iHigh(mSymbol,PERIOD_M1,iHighest(mSymbol,PERIOD_M1,MODE_HIGH,barCount,toShift));
   mLow   = iLow(mSymbol,PERIOD_M1,iLowest(mSymbol,PERIOD_M1,MODE_LOW,barCount,toShift));
   mClose = iClose(mSymbol,PERIOD_M1,toShift);
printf( "[%d]COM 開始時刻=>%s<  終了時刻=>%s<　始値=>%s<   高値=>%s<   安値=>%s<   終値=>%s<" , __LINE__,
         TimeToString(mFromTime),
         TimeToString(mToTime),
         DoubleToString(mOpen,  5),
         DoubleToString(mHigh,  5),
         DoubleToString(mLow,   5),
         DoubleToString(mClose, 5)
      );
}


// オシレーター系テクニカル指標を使った売買シグナル。
//WPRが-80以下の場合は、過剰売りとみなして、買いシグナル
//逆に、WPRが-20以上の場合は、過剰買いととみなして、売りシグナル
//
//RSIが30以下の場合は、市場が過剰売りの状態とみなして、買いシグナル。
//RSIが70以上の場合は、市場が過剰買いの状態とみなして、売りシグナル。/
//
//Stochastic Oscillatorの%K値が20以下の場合は、市場が過剰売りの状態とみなして、買いシグナル。
//Stochastic Oscillatorの%K値が80以上の場合は、市場が過剰買いの状態とみなして、売りシグナル
int judge_BuySellSignal_Oscillator(string mSymbol,
                                   int    &mWPR_Signal, // WPRを使ったシグナル。BUY_SIGNAL, SELL_SIGNAL, NO_SIGNAL
                                   int    &mRSI_Signal, // RSIを使ったシグナル。BUY_SIGNAL, SELL_SIGNAL, NO_SIGNAL
                                   int    &mSTOC_Signal, // Stochasticを使ったシグナル。BUY_SIGNAL, SELL_SIGNAL, NO_SIGNAL
                                   int    &mTotal_Signal // 3つのシグナルのうち1つ以上がBUY_SIGNALかつSELL_SIGNALが無ければ、BUY_SIGNAL
                                   ) {
   mWPR_Signal   = NO_SIGNAL;
   mRSI_Signal   = NO_SIGNAL;
   mSTOC_Signal  = NO_SIGNAL;
   mTotal_Signal = NO_SIGNAL;
   
   //WPRが-80以下の場合は、過剰売りとみなして、買いシグナル
   //逆に、WPRが-20以上の場合は、過剰買いととみなして、売りシグナル
   double mWPR = iWPR(mSymbol,0,14,1);
   if(mWPR <= -80.0) {
      mWPR_Signal = BUY_SIGNAL;
   }
   else if(mWPR >= -20.0) {
      mWPR_Signal = SELL_SIGNAL;   
   }
   else {
      mWPR_Signal = NO_SIGNAL;   
   }
   
   //RSIが30以下の場合は、市場が過剰売りの状態とみなして、買いシグナル。
   //RSIが70以上の場合は、市場が過剰買いの状態とみなして、売りシグナル。/   
	double RSI_9  = NormalizeDouble(iRSI(mSymbol, 0,  9, PRICE_CLOSE,1), global_Digits);
	double RSI_26 = NormalizeDouble(iRSI(mSymbol, 0, 26, PRICE_CLOSE,1), global_Digits);
	double RSI_52 = NormalizeDouble(iRSI(mSymbol, 0, 52, PRICE_CLOSE,1), global_Digits);
	//3点がlowLineより下で売られ過ぎ、
	//かつ、上からRSI_9、RSI_26、RSI52の順
	//以上を満たした時に買い
	double RSI_lowLine  = 30.0;
	double RSI_highLine = 70.0;
	if(
	   (RSI_9 < RSI_lowLine  && RSI_26 < RSI_lowLine  && RSI_52 < RSI_lowLine )  //3点がlowLineより下
	      &&
    	(RSI_9 > RSI_26 && RSI_26 > RSI_52 )   //上からRSI_9、RSI_26、RSI52の順
     ) { 
			mRSI_Signal = BUY_SIGNAL;
	}
	//3点がhighLineより上で買われ過ぎ、
	//かつ、上からRSI_52、RSI_26、RSI9の順で
	//以上を満たした時に売り
	else if(
    		( RSI_9 > RSI_highLine && RSI_26 > RSI_highLine && RSI_52 > RSI_highLine)  ////3点がhighLineより上
    		   &&
    		( RSI_9 < RSI_26 && RSI_26 < RSI_52 )   //上からRSI_52、RSI_26、RSI9の順
      ) {  
			mRSI_Signal = SELL_SIGNAL;
	}
	else {
	   mRSI_Signal = NO_SIGNAL;
	}


   //Stochastic Oscillatorの%K値が20以下の場合は、市場が過剰売りの状態とみなして、買いシグナル。
   //Stochastic Oscillatorの%K値が80以上の場合は、市場が過剰買いの状態とみなして、売りシグナル
   double Stoc_MAIN = iStochastic(mSymbol, 0, 5, 3, 3, 0, 0, MODE_MAIN, 1);
   if(Stoc_MAIN <= 20.0) {
      mWPR_Signal = BUY_SIGNAL;
   }
   else if(Stoc_MAIN >= 80.0) {
      mWPR_Signal = SELL_SIGNAL;   
   }
   else {
      mWPR_Signal = NO_SIGNAL;   
   }

   if( (mWPR_Signal != SELL_SIGNAL && mRSI_Signal != SELL_SIGNAL && mSTOC_Signal != SELL_SIGNAL)
         && 
       (mWPR_Signal == BUY_SIGNAL || mRSI_Signal == BUY_SIGNAL || mSTOC_Signal == BUY_SIGNAL) ){
      mTotal_Signal = BUY_SIGNAL;
   }
   else if( (mWPR_Signal != BUY_SIGNAL && mRSI_Signal != BUY_SIGNAL && mSTOC_Signal != BUY_SIGNAL)
         && 
       (mWPR_Signal == SELL_SIGNAL || mRSI_Signal == SELL_SIGNAL || mSTOC_Signal == SELL_SIGNAL) ){
      mTotal_Signal = SELL_SIGNAL;
   }
   
   return mTotal_Signal;	
}



//+------------------------------------------------------------------+
//| オープン中のオーダーを列挙する                   　　　　　      |
//+------------------------------------------------------------------+
 string readOpenOders() {	
	string strBuf ="";
	int orderType = 0;

	for(int j = OrdersTotal() - 1; j >= 0; j--){					
      		if(OrderSelect(j, SELECT_BY_POS, MODE_TRADES) == false) break;				

		datetime doneFlag = OrderCloseTime();				
	  	if(doneFlag == 0) {     //オーダーが決済されていない時、その内容をバッファに追加する。				
     		        strBuf = strBuf + "番号＝" + DoubleToStr(j, 0) + "\n";//番号				
			strBuf = strBuf + "通貨ペア＝" + OrderSymbol() + "\n";//通貨ペア			
			//売買区分			
			orderType = OrderType();
			
                        if(orderType == OP_BUY) strBuf = strBuf + "売買区分＝買" + "\n";			
			else if(orderType == OP_SELL) strBuf = strBuf + "売買区分＝売" + "\n";		
			else strBuf = strBuf + "売買区分＝" +  DoubleToStr(orderType, 0) + "\n";
                        
                        strBuf = strBuf + "マジックナンバー = " + IntegerToString(OrderMagicNumber()) + "\n";				
 			strBuf = strBuf + "約定値＝" +  DoubleToStr(OrderOpenPrice(),5) + "\n";//約定値			
			strBuf = strBuf + "約定数＝" +  DoubleToStr(OrderLots(),2) + "\n";//約定数			
			strBuf = strBuf + "約定時間＝" + TimeToStr(OrderOpenTime(), TIME_SECONDS) + "\n";//約定時間			
			strBuf = strBuf + "含み損益＝" +  DoubleToStr(OrderProfit(),5) + "\n";//含み損益			
			

			strBuf = strBuf + "========================" + "\n";			
		}				
	}
	return strBuf;
}		



//
//ファイルに文字列を書き込む
//
int mFileWrite(string mFileName, string mWrittenData) {
  int handle;

  //ファイルは terminal_directory\experts\files フォルダ（テストの場合は terminal_directory\tester\files）
  //または、そのサブフォルダにあるものだけ、開くことができます。
  handle=FileOpen(mFileName, FILE_TXT | FILE_WRITE, ';'); 
  
  if(handle <= 0) return handle;

/*【参考】文字列をカンマで分割する
  string sep=",";               // 区切り文字 
  ushort u_sep;                 // 区切り文字のコード 
  string result[];              // 分割された文字列を受け取る配列 
  int sepNum                    // 分割された文字列の個数

  //--- 区切り文字のコードを取得する 
  u_sep = StringGetCharacter(sep,0);
 
  //--- 文字列を部分文字列に分ける 
  sepNum = StringSplit(to_split,u_sep,result); 
*/

  if(handle>0)
    {
     FileWrite(handle, mWrittenData);
     FileClose(handle);
    }
    return 0;
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
    

