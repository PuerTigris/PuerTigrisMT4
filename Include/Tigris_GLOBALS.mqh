

//*************************************************
//*************************************************
// 最適化した際に変数の値を1か所で変更できるよう、このファイルを作成した。
//*************************************************
//*************************************************
//
//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
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

// 01FRAC
int FRACTALSPAN   = 150;// この値はフラクタルの山と谷を各２つずつ探すために使う。いくつのシフトをさかのぼってフラクタルの山と谷を探すか。;
int FRACTALADX    = 20; // 逆張りをする時、ADXがいくつ未満であれば、トレンドが弱いと判断するか。→　成績が悪いため、逆張りはせず、シグナルを取り消すのみ。
int FRACTALMETHOD = 2;  // 1:フラクタルのみ、2:アリゲーターによるトレンド追加。3:直近のフラクタルを結んだ線の傾きを判断。

// 04BB
double BBandSIGMA = 0.5  ;        //ボリンジャーバンドで逆張りを入れるσ値。4σで逆張りするなら4。

// 07STOCEMA
double STOCEMALow  = 30.0;       //ストキャスティクスのLowライン							
double STOCEMAHigh = 70.0;       //ストキャスティクスのHighライン	


// 08WPR
double WPRLow         = -70;   //ウィリアムズWPRのLow						
double WPRHigh        = -90;   //ウィリアムズWPRのHigh	「-20%を超えれば買われ過ぎで「売りサイン」
int    WPRgarbage     = 20; //過去WPRgarbage個のWPRのうち、WPRgarbageRate％の割合でWPRLowを下回っている個数があれば売りとみなす（ガーベージボトム）
double WPRgarbageRate = 40.0;

// 10GMMA
double GMMAWidth  = 0.25;// 直前（SHIFT=1）の陽線・陰線が、さらに1つ前（SHIFT=1）の陽線・陰線と比較して、数％以上であれば、取引をする。単位は、％。
double GMMAHigher = 65.0;	// RSIがこの値以下ならば、取引する						
double GMMALower  = 25.0; // RSIがこの値以上ならば、取引する。							
int    GMMALimmit = 15; // ロングの場合は、直近の高値、ショートの場合は直近の安値を更新していた場合のみ、取引。単位は本数（＝SHIFT数）

// 11KAIRI
int KAIRISPAN      = 200;							
int KAIRIBORDER    = 9;							
int KAIRIMA_Method = 2; //0から2まで							
int KAIRIApply     = 6;     //0から6まで							
int KAIRIMA_Period = 20;//移動平均iMAを計算する期間	

// 12SAR
double SAR_ADX = 5.0;  //パラボリックSARにおいてこの値より上で取引を行う。

// 14RSIMACD
double ENTRYRSI_highLine = 10.0; //RSIのハイライン。
double ENTRYRSI_lowLine  = 50.0; //RSIのロウライン。	

// 15MACDRCI
double RCIhighLine = -45.0;//
double RCIlowLine  = 75.0;//

// 16ICHI
int ICHIMOKU_SPANTYPE = 1; // 0or1。一目均衡表データを取得するための設定値セット。
                           // 0の時、転換線期間=9、基準線期間=26、先行スパン期間=52
                           // 1の時、転換線期間=7、基準線期間=21、先行スパン期間=42
int ICHIMOKU_METHOD   = 3; //1～5
                           // １．基準線と転換線のクロス　＝ ICHIMOKU_METHOD = 1
                           // ２．遅行スパンと価格のクロス＝ ICHIMOKU_METHOD = 2。ただし、上記１も満たすこと。
                           // ３．雲のブレイクアウト　　　＝ ICHIMOKU_METHOD = 3。ただし、上記１、２も満たすこと。
                           // ４．基準線と価格のクロス　　＝ ICHIMOKU_METHOD = 4。ただし、上記１～３も満たすこと。
                           // ５．雲のねじれ　　　　　　　＝ ICHIMOKU_METHOD = 5。ただし、上記１～４も満たすこと。
                          
// 17KAGI
double KAGIPips    = 24.5;// このPIPS数を超えた上下があった場合に、カギを更新する。
int    KAGISize    = 10; // 何本前のシフトからカギの計算をするか。
int    KAGIMethod  = 1;  // 1:一段抜きで売買、2:三尊で売買、3:五瞼で売買

// 18CORR
int CORREL_TF_SHORTER = 5;     //0から9。2は、PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
int CORREL_TF_LONGER  = 8;     //0から9。PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
double CORRELHigher   = 0.225; //-1.0～+1.0
double CORRELLower    = -0.225;  //-1.0～+1.0
int CORREL_period     = 100;

// 19MS
int    MSTFIndex    = 5;   // 0から9。2は、PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
double MSMoveSpeed  = 3.0; // 単位時間当たり、何pips移動するか。15分足で計算した時、大きくても10前後。
int    MSJUDGELEVEL = 3;   // 1～3。1:スピードの正負のみ。2:MAとMACDどちらかのGCやDCが条件を満たす。3:MAとMACD両方のGCやDCが条件を満たす。

// 20TBB                          
double TBBSigma    = 2.5;  // 何σの値を超えた時に売買シグナルを設定するか。
int TBTimeframe = 0;  // 計算対象とする時間軸

// 21RCISWING
int    RCISWING_LEN               = 9;    // 2以上9以下。トレンドを判定する時に何本の足を見るか。最大でも9＝短期線(RCI9)の期間数。
int    RCISWING_SWINGLEG          = 3;    // 6以上。スイングハイ・ローを計算する時に何本の足を見るか。通常は、6。
double RCISWING_EXCLUDE_PER       = 2.5;  // スイングハイ、スイングローのRCISWING_EXCLUDE_PERパーセントを取引禁止とする。
double RCISWING_RCI_TOO_BUY       = 80.0; // RCIがこの値以上なら買われすぎ＝売りサイン。RCIは、-100～+100。
double RCISWING_RCI_TOO_SELL      = -80.0;// RCIがこの値以下なら売られすぎ＝買いサイン。RCIは、-100～+100。
int    RCISWING_TRENDLEVEL_UPPER  = 2;    // 1～4。-4までは可能。とても強い上昇、強い上昇などのどのレベル以上なら良しとするか。
int    RCISWING_TRENDLEVEL_DOWNER = -1;   // -1～-4。4までは可能。とても強い下落、強い下落などのどのレベル以下ら良しとするか。

// 23ADXMA
int ADXMA_LONGMAMODE  = 1;  // SMA200を計算する際に使用。ENUM_MA_METHODの値である0,1,2,3のいずれか。デフォルト値は0(MODE_SMA)。
int ADXMA_SHORTMAMODE = 3;  // EMA10を計算する際に使用。 ENUM_MA_METHODの値である0,1,2,3のいずれか。デフォルト値は1(MODE_EMA)。
   // ENUM_MA_METHOD
   // ID        値   詳細
   // MODE_SMA  0    単純移動平均
   // MODE_EMA  1    指数移動平均
   // MODE_SMMA 2    平滑移動平均
   // MODE_LWMA 3    加重移動平均
int    ADXMA_SLOPESPAN            = 3;   // ADXの傾きを計算する際のシフト数。2以上100未満。
double ADXMA_LS_MIN_DISTANCE_PIPS = 5; // SMA200とEMA10の距離（絶対値）が、この値以上の時にのみ取引実行。単位はPIPS。

// 24ZZ
int ZigzagDepth     = 13;
int ZigzagDeviation = 10;
int ZigzagBackstep  = 7;
int ZigzagTradePattern = 1;

// 25PinBAR
int    PinBarMethod       = 1;     // 1:No1：順張りピンバー手法, 2:No3 ピンバー押し・戻り手法, 3:1と2, 4:NoX 予約
                                   // 001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=NoX予約, 101(5)=No1とNoX  
int    PinBarTimeframe    = 5;     // 計算に用いる時間軸
int    PinBarBackstep     = 15;    // 大陽線、大陰線が発生したことを何シフト前まで確認するか
double PinBarBODY_MIN_PER = 80.0;  // 実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
double PinBarPIN_MAX_PER  = 25.0;  // 実体が髭のナンパ―セント以下であればピンと判断するか

// 99RandomTrade
int    RTTickCount = 1;
int    RTMethod = 1;           // 1:ランダムに売買を判断する。2:トレンドも考慮して売買を判断する
double RTthreshold_PER = 50.0; // 売買判断をする閾値（threshold）。乱数(0～32767)が、32767 * RTthreshold_PER / 100以上なら売り。未満なら、買い。

// 95 RVI
double Sigma2_Min_Width_POINT = 0.05;
int average_period = 7;   //RVIの期間

// 94 MRA
int    MRA_DEGREE = 9;      // 重回帰分析をする際の次数。次数は2以上にすること
int    MRA_EXP_TYPE = 1;    // 重回帰分析をする際の説明変数データ群のデータパターン。1:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, slopeH4、2:MA5 - MA25, MACD-Signal, BB_UP - BB_DOWN, rsi
int    MRA_DATA_NUM = 100;  // 重回帰分析をする際のデータ件数。次数＋２以上にすること
double MRA_TP_PIPS = 5.0;   // 利益がこの値を超えそうであれば、シグナルを発する。
double MRA_SL_PIPS = 5.0;   // 利益がこの値を超えそうであれば、シグナルを解消する。
int    MRA_FUTURE_STEP = 1; // シグナル判断にいくつ先の予測値まで使うか。
//
//
/* ↓20220415XM環境向け↓ */
//
//
//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	

//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
/*
// 01FRAC
int FRACTALSPAN   = 200;// この値はフラクタルの山と谷を各２つずつ探すために使う。いくつのシフトをさかのぼってフラクタルの山と谷を探すか。;
int FRACTALADX    = 25; // 逆張りをする時、ADXがいくつ未満であれば、トレンドが弱いと判断するか。→　成績が悪いため、逆張りはせず、シグナルを取り消すのみ。
int FRACTALMETHOD = 4;  // 1:フラクタルのみ、2:アリゲーターによるトレンド追加。3:直近のフラクタルを結んだ線の傾きを判断。

// 04BB
int BBandSIGMA = 2  ;        //ボリンジャーバンドで逆張りを入れるσ値。4σで逆張りするなら4。

// 07STOCEMA
int STOCEMAHigh = 10;       //ストキャスティクスのHighライン	
int STOCEMALow  = 40;       //ストキャスティクスのLowライン							

// 08WPR
double WPRLow         = -75;   //ウィリアムズWPRのLow						
double WPRHigh        = -65;   //ウィリアムズWPRのHigh	「-20%を超えれば買われ過ぎで「売りサイン」
int    WPRgarbage     = 30; //過去WPRgarbage個のWPRのうち、WPRgarbageRate％の割合でWPRLowを下回っている個数があれば売りとみなす（ガーベージボトム）
double WPRgarbageRate = 85.0;

// 10GMMA
double GMMAWidth  = 0.85;// 直前（SHIFT=1）の陽線・陰線が、さらに1つ前（SHIFT=1）の陽線・陰線と比較して、数％以上であれば、取引をする。単位は、％。
double GMMAHigher = 90;	// RSIがこの値以下ならば、取引する						
double GMMALower  = 45; // RSIがこの値以上ならば、取引する。							
int    GMMALimmit = 5; // ロングの場合は、直近の高値、ショートの場合は直近の安値を更新していた場合のみ、取引。単位は本数（＝SHIFT数）

// 11KAIRI
int KAIRISPAN      = 70;							
int KAIRIBORDER    = 3;							
int KAIRIMA_Method = 1; //0から2まで							
int KAIRIApply     = 6;     //0から6まで							
int KAIRIMA_Period = 25;//移動平均iMAを計算する期間	

// 12SAR
double SAR_ADX = 25.0;  //パラボリックSARにおいてこの値より上で取引を行う。

// 14RSIMACD
double ENTRYRSI_highLine = 25.0; //RSIのハイライン。
double ENTRYRSI_lowLine  = 25.0; //RSIのロウライン。	

// 15MACDRCI
double RCIhighLine =  0.725;//
double RCIlowLine  = -0.65;//

// 16ICHI
int ICHIMOKU_SPANTYPE = 0; // 0or1。一目均衡表データを取得するための設定値セット。
                           // 0の時、転換線期間=9、基準線期間=26、先行スパン期間=52
                           // 1の時、転換線期間=7、基準線期間=21、先行スパン期間=42
int ICHIMOKU_METHOD   = 5; //1～5
                           // １．基準線と転換線のクロス　＝ ICHIMOKU_METHOD = 1
                           // ２．遅行スパンと価格のクロス＝ ICHIMOKU_METHOD = 2。ただし、上記１も満たすこと。
                           // ３．雲のブレイクアウト　　　＝ ICHIMOKU_METHOD = 3。ただし、上記１、２も満たすこと。
                           // ４．基準線と価格のクロス　　＝ ICHIMOKU_METHOD = 4。ただし、上記１～３も満たすこと。
                           // ５．雲のねじれ　　　　　　　＝ ICHIMOKU_METHOD = 5。ただし、上記１～４も満たすこと。
                          
// 17KAGI
double KAGIPips    = 4.5;  // このPIPS数を超えた上下があった場合に、カギを更新する。
int    KAGISize    = 60; // 何本前のシフトからカギの計算をするか。
int    KAGIMethod  = 1;  // 1:一段抜きで売買、2:三尊で売買、3:五瞼で売買

// 18CORR
int CORREL_TF_SHORTER = 1;   //0から9。2は、PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
int CORREL_TF_LONGER  = 5;   //0から9。PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
double CORRELHigher   = 0.65; //-1.0～+1.0
double CORRELLower    = -0.9;//-1.0～+1.0
int CORREL_period     = 100;

// 19MS
int    MSTFIndex    = 4;    // 0から9。2は、PERIOD_M5; getTimeFrame(x)でPERIOD_M1などに変換可能。
double MSMoveSpeed  = 2.75;  // 単位時間当たり、何pips移動するか。15分足で計算した時、大きくても10前後。
int    MSJUDGELEVEL = 2;    // 1～3。1:スピードの正負のみ。2:MAとMACDどちらかのGCやDCが条件を満たす。3:MAとMACD両方のGCやDCが条件を満たす。

// 20TBB                          
int TBBSigma    = 4;  // 何σの値を超えた時に売買シグナルを設定するか。
int TBTimeframe = 0;  // 計算対象とする時間軸

// 21RCISWING
int    RCISWING_LEN           = 6;    // 2以上9以下。トレンドを判定する時に何本の足を見るか。最大でも9＝短期線(RCI9)の期間数。
int    RCISWING_SWINGLEG      = 9;    // 6以上。スイングハイ・ローを計算する時に何本の足を見るか。通常は、6。
double RCISWING_EXCLUDE_PER   = 5.0; // スイングハイ、スイングローのRCISWING_EXCLUDE_PERパーセントを取引禁止とする。
double RCISWING_RCI_TOO_BUY   = 70.0; // RCIがこの値以上なら買われすぎ＝売りサイン。RCIは、-100～+100。
double RCISWING_RCI_TOO_SELL  = -70.0;// RCIがこの値以下なら売られすぎ＝買いサイン。RCIは、-100～+100。
int    RCISWING_TRENDLEVEL_UPPER  = 1;  // 1～4。-4までは可能。とても強い上昇、強い上昇などのどのレベル以上なら良しとするか。
int    RCISWING_TRENDLEVEL_DOWNER = -1; // -1～-4。4までは可能。とても強い下落、強い下落などのどのレベル以下ら良しとするか。

// 23ADXMA
int ADXMA_LONGMAMODE  = 2;  // SMA200を計算する際に使用。ENUM_MA_METHODの値である0,1,2,3のいずれか。デフォルト値は0(MODE_SMA)。
int ADXMA_SHORTMAMODE = 3;  // EMA10を計算する際に使用。 ENUM_MA_METHODの値である0,1,2,3のいずれか。デフォルト値は1(MODE_EMA)。
   // ENUM_MA_METHOD
   // ID        値   詳細
   // MODE_SMA  0    単純移動平均
   // MODE_EMA  1    指数移動平均
   // MODE_SMMA 2    平滑移動平均
   // MODE_LWMA 3    加重移動平均
int ADXMA_SLOPESPAN            = 5;  // ADXの傾きを計算する際のシフト数。2以上100未満。
int ADXMA_LS_MIN_DISTANCE_PIPS = 11; // SMA200とEMA10の距離（絶対値）が、この値以上の時にのみ取引実行。単位はPIPS。

// 24ZZ
int ZigzagDepth     = 18;
int ZigzagDeviation = 5;
int ZigzagBackstep  = 3;
*/





