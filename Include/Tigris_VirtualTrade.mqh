//+------------------------------------------------------------------+
//|  仮想取引関連部品                                                   |
//|  Copyright (c) 2016 トラの親 All rights reserved.                   |
//|                                                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| ヘッダーファイル読込                                             |
//+------------------------------------------------------------------+
#include <Tigris_COMMON.mqh>
#include <Tigris_GLOBALS.mqh>
//#include <Puer_STAT.mqh>  // 偏差や平均を計算する関数calcMeanAndSigmaを使うため。
#include <Tigris_Statistics.mqh>
//+------------------------------------------------------------------+
//| 定数宣言部                                                       |
//+------------------------------------------------------------------+
#define VTRADENUM_MAX 300000   // 仮想取引の最大数。
#define VOPTPARAMSNUM_MAX 10000 // 仮想取引用パラメータセットの最大数。
#define HISTORICAL_NUM 5
//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
double GENERALRULE_PER = 60.0;     // 各指標が、一般的に言われている条件のうち、この数値%以上満たしていれば、 一般的な条件を満たしていると判断する閾値。
double MATCHINDEX_PER  = 90.0;     // 各指標が、μ±n×σの範囲内（範囲外）の時に、条件を満たしていると判断する閾値。条件を満たした指標÷指標総数
double RISKREWARD_PERCENT = 100.0; //リスクリワード率がこの値未満になれば、その戦略の使用禁止。 

extern bool VT_FILEIO_FLAG = false;// trueの時にファイル出力関数を実行する。
extern int    VTRADEBACKSHIFTNUM  = 500;  //過去500シフトで仮想取引が発生すれば登録する。

//+------------------------------------------------------------------+
//| グローバル変数宣言                                                     |
//+------------------------------------------------------------------+
int Last_Real_TradeType = NO_SIGNAL; // 実取引と仮想取引の差分を調べるための変数。　
datetime Last_Real_TradeTime = 0; // 実取引と仮想取引の差分を調べるための変数。　
int Last_V_TradeType = NO_SIGNAL; // 実取引と仮想取引の差分を調べるための変数。　
datetime Last_V_TradeTime = 0; // 実取引と仮想取引の差分を調べるための変数。　


datetime lastForceSettlementTime = 0;  // 最後にv_do_ForcedSettlementを実行した時間

struct st_vOrder   //仮想取引を保持するための構造体。
  {
   string            externalParam;   // 仮想最適化の場合のみ利用する。^区切りの外部パラメータ。
   string            strategyID;      // 21:RCISWING, 20:TrendBB, 19:MoveSpeedなど
   string            symbol;          // EURUSD-CDなど
   int               ticket;          // 通し番号
   int               timeframe;       // 【参考情報であり使い道無し】仮想取引を発注する際に用いた時間軸。時間軸。0は不可。
   // PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4
   // PERIOD_D1, PERIOD_W1, PERIOD_MN1
   int               orderType;       // OP_BUYかOPSELL
   datetime          openTime;        // 約定日時。datetime型。
   double            lots;            // ロット数
   double            openPrice;       // 新規建て時の値
   double            orderTakeProfit; // 利益確定の値
   double            orderStopLoss;   // 損切の値
   double            closePrice;      // 決済値
   datetime          closeTime;       // 決済日時。datetime型。
   double            closePL;         // 決済損益
   double            estimatePrice;   // 評価値
   datetime          estimateTime;    // 評価日時。datetime型。
   double            estimatePL;      // 評価損益。単位はPIPS
  };
st_vOrder st_vOrders[VTRADENUM_MAX];   // 仮想取引データ

struct st_vOrderPL {  //戦略別・通貨ペア別・タイムフレーム別の損益集計結果を保持するための構造体。
   string            strategyID;      // 21:RCISWING, 20:TrendBB, 19:MoveSpeedなど
   string            symbol;          // EURUSD-CDなど
   int               timeframe;       // 【参考情報であり使い道無し】時間軸。0は不可。
   // PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4
   // PERIOD_D1, PERIOD_W1, PERIOD_MN1
   datetime          analyzeTime;     // 評価日時。datetime型。
   int               win;             // 評価時点の勝ち数。未決済取引は、評価益が出ている取引数とする。
   double            Profit;          // 評価時点の実現利益＋評価利益。単位はPIPS。
   int               lose;            // 評価時点の敗け。未決済取引は、評価損が出ている取引数とする。
   double            Loss;            // 評価時点の実現損失＋評価損失。単位はPIPS。
   int               even;            // 評価時点の引き分け。未決済取引は、評価損益が0.0の取引数とする。
   double            maxDrawdownPIPS; // 評価時点のドローダウン（PIPS)。
   double            riskRewardRatio; // リスクリワード率。利確の平均÷損切の平均。全勝で負け数loseが0の時はDOUBLE_VALUE_MAX。勝ち、負けともに０件の時は０。
   double            ProfitFactor;    // プロフィットファクタPF。取引がない場合など、異常値DOUBLE_VALUE_MIN以外は０以上。
   datetime          latestTrade_time[HISTORICAL_NUM]; // 直近５件の取引の時間　[0]が一番古く、datetimeが小さい
   double            latestTrade_PL[HISTORICAL_NUM];   // 直近５件の取引の損益
   double            latestTrade_WeightedAVG;          // 直近５件の取引の損益の加重平均
  };
// https://www.sisutoreshouken.com/
// ↑正確なURLは、Googleで「FX自動売買のリスクリターン率の目安とは？」をキーとして検索すること。
/* ＜必要な部分だけ抜粋＞
   リスクリターン率とは、対象期間内の総損益の大きさを最大ドローダウンの大きさで割った数値である。
   例えば、総損益が1,000pips、最大ドローダウンが500pipsであった場合、リスクリターン率は2.0となる。
   リスクリターン率の数値が小さければ、総損益に対して最大ドローダウンの大きさが小さく、利益に対してリスクは小さいということを意味する。
   一方、リスクリターン率が大きければ、利益に対するリスクは大きいことを示す。
   FXの自動売買のリスクリターン率としては、2.0以上が好ましい。
   それ未満であると、利益に対して耐えることになるリスクが重くなってしまい、大切な資産を危険にさらすことになり得る。
   そして、勝敗を決める分け目となるのが、2.0というリスクリターン率の数値であろう。
   2.0以上の数値のストラテジーとなると、評判の悪い勝てない売買シグナルとなる例は少ない。
   よって、ミラートレーダーやMT4などの自動売買のストラテジーを決める際には、リスクリターン率が2.0以上の値をたたき出しているものを利用することをおすすめする。
   1.0未満は論外
   もし仮に、リスクリターン率が1.0未満のストラテジーを使ったらどうなるだろうか。
   たとえば、0.5となっているストラテジーの場合、1,000pipsの利益を上げるために2,000pipsのリスクを取ることを意味する。
   資産を増やすという目的を達成するために必要以上に過度にリスクを取ることは決しておすすめではない。
   安全を第一に考え、リスクリターン率が1.0未満となっているストラテジーは手元にはおかないのが鉄則であろう。
*/
st_vOrderPL st_vOrderPLs[VOPTPARAMSNUM_MAX];     // 戦略別・通貨ペア別・タイムフレーム別の損益集計結果

// 【ソート用】戦略別・通貨ペア別・タイムフレーム別の損益集計結果
st_vOrderPL sorted_st_vOrderPLs[VOPTPARAMSNUM_MAX]; // 【ソート用】戦略別・通貨ペア別・タイムフレーム別の損益集計結果
st_vOrderPL buf_st_vOrderPLs[VOPTPARAMSNUM_MAX];    // 【ソート用】途中経過を保存するため。戦略別・通貨ペア別・タイムフレーム別の損益集計結果
st_vOrderPL selected_st_vOrderPLs[VOPTPARAMSNUM_MAX];

struct st_vOrderIndex      // 仮想取引を約定した時点の各種指標値
  {
//20220223削除。指標の計算は、約定の戦略に依存しないため。 string            strategyID;      // VTなど  
   string            symbol;          // EURUSD-CDなど
   int               timeframe;       // 移動平均などを計算する際に用いる時間軸。0は不可。
   // PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4
   // PERIOD_D1, PERIOD_W1, PERIOD_MN1
   datetime          calcTime;      // 約定日時。datetime型。st_vOrders[].openTimeのいずれかと一致。
   // トレンド分析
   // 1 移動平均:MA
   int               MA_GC;              // ・ゴールデンクロス＝直近のクロスまでのシフト数:GC
   int               MA_DC;              // 　・デッドクロスの有無＝直近のクロスまでのシフト数:DC
   double            MA_Slope5;          // 　・傾き＝シフト5本、25本、75本の傾き:Slope
   double            MA_Slope25;
   double            MA_Slope75;
   // 2 ボリンジャーバンドBB
   double            BB_Width;        // ・約定価格がその当時の平均±n×σを満たすnの値。予想は、買いで利益が出るのはnが2以上。:Width
   // 3 一目均衡表:IK
   double            IK_TEN;          // ・転換線 - 基準線のPIPS。転換線が基準線を上抜けたら買い/下抜けたら売り　→　予想は、買いで利益が出るのはPIPSが正の時。:TENGC, TENDC
   double            IK_CHI;          // ・遅行線 - CloseのPIPS。遅行線がローソク足を上抜けたら買い/下抜けたら売り　→　予想は、買いで利益が出るのはPIPSが正の時。:CHIGC, CHIDC
   double            IK_LEG;          //　・（Close - 雲の近い方）のPIPS。ローソク足が雲を上抜けたら買い/下抜けたら売り　→　予想は、買いで利益が出るのはPIPSが正の時。:LEG
   // 4 MACD:MACD
   int               MACD_GC;            //　・ゴールデンクロス＝直近のクロスまでのシフト数:GC
   int               MACD_DC;            //　・デッドクロスの有無＝直近のクロスまでのシフト数:DC
   //
   // オシレーター分析
   // 1 RSI:RSI
   double            RSI_VAL;         // ・0%～100%の間で推移する数値。RSIが70％～80％を超えると買われ過ぎ、反対に20％～30％を割り込むと売られ過ぎのため、予想は、買いで利益が出るのは20％～30％付近。:VAL
   // 2 ストキャスティクス:STOC
   double            STOC_VAL;             //　・0%～100%の間で推移するスローストキャスティクスSlow％D。:VAL（MODE_MAINの値）
   //　　-「Slow％D」が0～20％にある時は、売られすぎゾーンと見て「買いサイン」。80～100％にある時は、買われすぎゾーンと見て「売りサイン」
   int            STOC_GC;       //　・「Slow％K」ラインが「Slow％D」を下から上に抜ける（ゴールデンクロス）＝直近のクロスまでのシフト数:GC
   int            STOC_DC;       //　　・「Slow％K」ラインが「Slow％D」を上から下に抜ける（デッドクロス）＝直近のクロスまでのシフト数:DC
   // 3 酒田五法（ローソク足の組み合わせのため、除外）
   // 4 RCI:RCI
   double            RCI_VAL;         // ・-100%～100%の間で推移する数値。予想は、買いで利益が出るのは-80％付近。売りで利益が出るのは+80％付近。:VAL

  };
st_vOrderIndex st_vOrderIndexes[VTRADENUM_MAX];   // 仮想取引データの約定時点の指標

struct st_vAnalyzedIndex   //戦略別・通貨ペア別・タイムフレーム別・売買区分別・損益別の各指標の平均と偏差。
  {
   int               stageID;      // DB書き込み時のみ使用する。計算根拠とした取引のステージ番号
   string            strategyID;   // 計算根拠とした取引の戦略名。
   string            symbol;       // 計算根拠とした取引の通貨ペア名。
   int               timeframe;    // 計算根拠とした指標の計算用時間軸。st_vOrderIndex.timeframeと一致すること。
   int               orderType;    // 計算根拠とした取引の売買区分。OP_BUYかOPSELL
   int               PLFlag;       // 計算根拠とした取引の売買区分。利益が出ている場合はvPROFIT=1、損失が出ている場合はvLOSS=-1
   datetime          analyzeTime;  // 評価日時。datetime型。
   // トレンド分析
   // 1 移動平均:MA
   double            MA_GC_MEAN;              // ・ゴールデンクロス＝直近のクロスまでのシフト数:GC
   double            MA_DC_MEAN;              // 　・デッドクロスの有無＝直近のクロスまでのシフト数:DC
   double            MA_Slope5_MEAN;       // 　・傾き＝シフト5本、25本、75本の傾き:Slope
   double            MA_Slope25_MEAN;
   double            MA_Slope75_MEAN;
   // 2 ボリンジャーバンドBB
   double            BB_Width_MEAN;
   // 3 一目均衡表:IK
   double            IK_TEN_MEAN;
   double            IK_CHI_MEAN;
   double            IK_LEG_MEAN;
   // 4 MACD:MACD
   double            MACD_GC_MEAN;
   double            MACD_DC_MEAN;
   //
   // オシレーター分析
   // 1 RSI:RSI
   double            RSI_VAL_MEAN;
   // 2 ストキャスティクス:STOC
   double            STOC_VAL_MEAN;
   double            STOC_GC_MEAN;
   double            STOC_DC_MEAN;
   // 4 RCI:RCI
   double            RCI_VAL_MEAN;

   // トレンド分析
   // 1 移動平均:MA
   double            MA_GC_SIGMA;
   double            MA_DC_SIGMA;
   double            MA_Slope5_SIGMA;
   double            MA_Slope25_SIGMA;
   double            MA_Slope75_SIGMA;
   // 2 ボリンジャーバンドBB
   double            BB_Width_SIGMA;
   // 3 一目均衡表:IK
   double            IK_TEN_SIGMA;
   double            IK_CHI_SIGMA;
   double            IK_LEG_SIGMA;
   // 4 MACD:MACD
   double            MACD_GC_SIGMA;
   double            MACD_DC_SIGMA;
   //
   // オシレーター分析
   // 1 RSI:RSI
   double            RSI_VAL_SIGMA;
   // 2 ストキャスティクス:STOC
   double            STOC_VAL_SIGMA;
   double            STOC_GC_SIGMA;
   double            STOC_DC_SIGMA;
   // 4 RCI:RCI
   double            RCI_VAL_SIGMA;

  };
st_vAnalyzedIndex st_vAnalyzedIndexesBUY_Profit;  // 買いで利益が出た仮想取引を対象とした指標の分析結果。
st_vAnalyzedIndex st_vAnalyzedIndexesBUY_Loss;    // 買いで損失が出た仮想取引を対象とした指標の分析結果。
st_vAnalyzedIndex st_vAnalyzedIndexesSELL_Profit; // 売りで利益が出た仮想取引を対象とした指標の分析結果。
st_vAnalyzedIndex st_vAnalyzedIndexesSELL_Loss;   // 売りで損失が出た仮想取引を対象とした指標の分析結果。

//    仮想取引用の外部パラメータセットの構造は次のとおり。
struct st_25PinOptParam {
   // いづれの項目も、初期値を外部パラメータの値とする。
   string strategyID;            // g_StratNameNN + 戦略別通し番号"@@NNNNN"とする。例えば、25PIN@@00001
   string MT4PathNo;             // MT4で最適化した際のパス番号
   string MT4PL;                 // MT4で最適化した際の損益
   string MT4TradeNum;           // MT4で最適化した際の取引数
   double TP_PIPS;               //【最適化:5.0～100.0。+5する＝×20】1約定あたりの利確pips数。負の時は、利確値の設定や強制利確をしない。
   double SL_PIPS;               //【実装保留】1約定当たりの損切pips数。SL_PIPS_PER設定時は上書きされる。負の時は、損切値の設定や強制損切をしない。
   double SL_PIPS_PER;           //【最適化:10.0～30.0。+10する＝×3】TP_PIPSに対するSL_PPIPSの割りあい。SL_PIPSを上書きする。負の時は、上書きしない。
   double FLOORING;              //【実装保留】損切値を、オープンから指定した値(PIP)の位置に変更する。PIPS数。負の数の場合は、何もしない。            
   bool   FLOORING_CONTINUE;     //【実装保留】trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。    
   int    TIME_FRAME_MAXMIN;     //【実装保留】1～9最高値、最安値の参照期間の単位。
   int    SHIFT_SIZE_MAXMIN;     //【実装保留】最高値、最安値の参照期間
   double ENTRY_WIDTH_PIPS;      //【実装保留】エントリーする間隔。PIPS数。
   double SHORT_ENTRY_WIDTH_PER; //【実装保留】ショート実施帯域。過去最高値から何パーセント下までショートするか
   double LONG_ENTRY_WIDTH_PER;  //【実装保留】ロング実施帯域。過去最安値から何パーセント上までロングするか
   double ALLOWABLE_DIFF_PER;    //【実装保留】価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値みなすか。 
   int    PinBarMethod;          //【最適化:1～7】001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5, 110(6)=No3とNo5, 111=No1とNo3とNo5
   int    PinBarTimeframe;       //【変動させない】ピンの計算に使う時間軸
   int    PinBarBackstep;        //【変動させない】大陽線、大陰線が発生したことを何シフト前まで確認するか
   double PinBarBODY_MIN_PER;    //【最適化:60.0～90.0。+10する＝×4】実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
   double PinBarPIN_MAX_PER;     //【最適化:10.0～30.0。+5する ＝×5】実体が髭のナンパ―セント以下であればピンと判断するか
};

struct st_18CORROptParam {
   // いづれの項目も、初期値を外部パラメータの値とする。
   string strategyID;            // g_StratNameNN + 戦略別通し番号"@@NNNNN"とする。例えば、25PIN@@00001
   datetime lastTradeTime;       // 連続取引防止用の最後に取引したシフトの開始時刻
   string MT4PathNo;             // MT4で最適化した際のパス番号
   string MT4PL;                 // MT4で最適化した際の損益
   string MT4TradeNum;           // MT4で最適化した際の取引数
   double TP_PIPS;               //【最適化:5.0～100.0。+5する＝×20】1約定あたりの利確pips数。負の時は、利確値の設定や強制利確をしない。
   double SL_PIPS;               //【実装保留】1約定当たりの損切pips数。SL_PIPS_PER設定時は上書きされる。負の時は、損切値の設定や強制損切をしない。
   double SL_PIPS_PER;           //【最適化:10.0～30.0。+10する＝×3】TP_PIPSに対するSL_PPIPSの割りあい。SL_PIPSを上書きする。負の時は、上書きしない。
   double FLOORING;              //【実装保留】損切値を、オープンから指定した値(PIP)の位置に変更する。PIPS数。負の数の場合は、何もしない。            
   bool   FLOORING_CONTINUE;     //【実装保留】trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。    
   int    TIME_FRAME_MAXMIN;     //【実装保留】1～9最高値、最安値の参照期間の単位。
   int    SHIFT_SIZE_MAXMIN;     //【実装保留】最高値、最安値の参照期間
   double ENTRY_WIDTH_PIPS;      //【実装保留】エントリーする間隔。PIPS数。
   double SHORT_ENTRY_WIDTH_PER; //【実装保留】ショート実施帯域。過去最高値から何パーセント下までショートするか
   double LONG_ENTRY_WIDTH_PER;  //【実装保留】ロング実施帯域。過去最安値から何パーセント上までロングするか
   double ALLOWABLE_DIFF_PER;    //【実装保留】価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値みなすか。 
   int    CORREL_TF_SHORTER;     //【最適化】0から9。2は、PERIOD_M5
   int    CORREL_TF_LONGER ;     //【最適化】0から9。2は、PERIOD_M5
   double CORRELLower;           //【最適化】相関係数がこれ以上であれば、シグナル発生候補
   double CORRELHigher;          //【最適化】相関係数がこれ以下であれば、シグナル発生候補
   int    CORREL_period;         //【実装保留】実体が髭のナンパ―セント以下であればピンと判断するか
};

struct st_08WPROptParam {
   // いづれの項目も、初期値を外部パラメータの値とする。
   string strategyID;            // g_StratNameNN + 戦略別通し番号"@@NNNNN"とする。例えば、25PIN@@00001
   string MT4PathNo;             // MT4で最適化した際のパス番号
   string MT4PL;                 // MT4で最適化した際の損益
   string MT4TradeNum;           // MT4で最適化した際の取引数
   double TP_PIPS;               //【最適化:5.0～100.0。+5する＝×20】1約定あたりの利確pips数。負の時は、利確値の設定や強制利確をしない。
   double SL_PIPS;               //【実装保留】1約定当たりの損切pips数。SL_PIPS_PER設定時は上書きされる。負の時は、損切値の設定や強制損切をしない。
   double SL_PIPS_PER;           //【最適化:10.0～30.0。+10する＝×3】TP_PIPSに対するSL_PPIPSの割りあい。SL_PIPSを上書きする。負の時は、上書きしない。
   double FLOORING;              //【実装保留】損切値を、オープンから指定した値(PIP)の位置に変更する。PIPS数。負の数の場合は、何もしない。            
   bool   FLOORING_CONTINUE;     //【実装保留】trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。    
   int    TIME_FRAME_MAXMIN;     //【実装保留】1～9最高値、最安値の参照期間の単位。
   int    SHIFT_SIZE_MAXMIN;     //【実装保留】最高値、最安値の参照期間
   double ENTRY_WIDTH_PIPS;      //【実装保留】エントリーする間隔。PIPS数。
   double SHORT_ENTRY_WIDTH_PER; //【実装保留】ショート実施帯域。過去最高値から何パーセント下までショートするか
   double LONG_ENTRY_WIDTH_PER;  //【実装保留】ロング実施帯域。過去最安値から何パーセント上までロングするか
   double ALLOWABLE_DIFF_PER;    //【実装保留】価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値みなすか。 
   double WPRLow;     //
   double WPRHigh;     //
   int    WPRgarbage;
   double WPRgarbageRate;

};

//
// 外部パラメーター、グローバル変数に上書きする前に保存しておく。。
//
double BUF_TP_PIPS;
double BUF_SL_PIPS;
double BUF_SL_PIPS_PER;
double BUF_FLOORING;
bool   BUF_FLOORING_CONTINUE;
int    BUF_TIME_FRAME_MAXMIN;
int    BUF_SHIFT_SIZE_MAXMIN;
double BUF_ENTRY_WIDTH_PIPS;
double BUF_SHORT_ENTRY_WIDTH_PER;
double BUF_LONG_ENTRY_WIDTH_PER;
double BUF_ALLOWABLE_DIFF_PER;
int    BUF_PinBarMethod;
int    BUF_PinBarTimeframe;
int    BUF_PinBarBackstep;
double BUF_PinBarBODY_MIN_PER;
double BUF_PinBarPIN_MAX_PER;

int    BUF_CORREL_TF_SHORTER;
int    BUF_CORREL_TF_LONGER;
double BUF_CORRELLower; 
double BUF_CORRELHigher; 
int    BUF_CORREL_period;

double BUF_WPRLow;
double BUF_WPRHigh;
int    BUF_WPRgarbage;
double BUF_WPRgarbageRate;

//
// 条件に応じて配列から要素を抽出する際の引数
// 例）mTradeNum以上を選ぶなら1、mTradeNumと一致なら0、mTradeNum以下なら-1
int    g_Greater_Eq = 1;
int    g_Lower_Eq   = -1;
int    g_Equal      = 0;


datetime vOPENTIME  = 0;  // 仮想取引を新規約定する時間を指定する場合にdatetime型データを代入する。
datetime vCLOSETIME  = 0;  // 仮想取引を決済する時間を指定する場合にdatetime型データを代入する。
int      vPROFIT     = 1;  // 仮想取引利益が発生している場合。
int      vPL_DEFAULT = 0;   // 仮想取引損失益が、vPROFITとvLOSSのどちらでもない。
int      vLOSS       = -1; // 仮想取引損失益が発生している場合。
int      vBUY_PROFIT  = 1; // 買い＆利益の場合を指す。
int      vBUY_LOSS    = 2; // 買い＆損失の場合を指す。
int      vSELL_PROFIT = 3; // 売り＆利益の場合を指す。
int      vSELL_LOSS   = 4; // 売り＆損失の場合を指す。


// 仮想取引用トレーディングライン
double   g_v_past_max     = DOUBLE_VALUE_MIN; // 過去の最高値
datetime g_v_past_maxTime = -1;               // 過去の最高値の時間
double   g_v_past_min     = DOUBLE_VALUE_MIN; // 過去の最安値
datetime g_v_past_minTime = -1;               // 過去の最安値の時間
double   g_v_past_width   = DOUBLE_VALUE_MIN; // 過去値幅。past_max - past_min
double   g_v_long_Min     = DOUBLE_VALUE_MIN; // ロング取引を許可する最小値
double   g_v_long_Max     = DOUBLE_VALUE_MIN; // ロング取引を許可する最大値
double   g_v_short_Min    = DOUBLE_VALUE_MIN; // ショート取引を許可する最小値
double   g_v_short_Max    = DOUBLE_VALUE_MIN; // ショート取引を許可する最大値

// ソート
int      g_vSortDESC =  1;  // DESC（降順）なら+1、ASC(昇順）なら-1
int      g_vSortASK  = -1; // DESC（降順）なら+1、ASC(昇順）なら-1



//+------------------------------------------------------------------+
//| 実行時点のASK、BIDを使って、                                     |
//| 仮想取引の利確、損切を設定する。                                 |
//| ※MODE_ASK、MODE_BIDを使っていることから、過去日付では使えない。 |
//+------------------------------------------------------------------+
bool v_update_AllOrdersTPSL(double mTP, double mSL)  {
   int mOrderTicket = 0;
   int mBUYSELL   = 0;
   double minSL   = 0.0;
   double mOpen   = 0.0;
   double mTP_Order  = 0.0;
   double mSL_Order  = 0.0;
   double mOrderLots = 0.0;
   int mFlag       = true;  // OrderModify実行結果。
   double mTP_BUY  = 0.0;
   double mSL_BUY  = 0.0;
   double mTP_SELL = 0.0;
   double mSL_SELL = 0.0;

   double mMarketinfoMODE_ASK = 0.0;
   double mMarketinfoMODE_BID = 0.0;
   double mMarketinfoMODE_POINT = global_Points;
   double mMarketinfoMODE_STOPLEVEL = global_StopLevel;
   bool   flag_avoid_v_update_AllOrdersTPSL = false;    // 1件ずつ仮想取引の利確、損切設定を計算する際に、通常ロジックを適用しない時(ZZ, FRAC)にtrue
   bool   is_flag_avoid_v_update_AllOrdersTPSL = false; // 1件でも、通常ロジックを適用しない時(ZZ, FRAC)にtrue

   // 引数チェック
   if(mTP < 0.0 && mSL < 0.0)  {
      return false;
   }

   mMarketinfoMODE_ASK = MarketInfo(global_Symbol,MODE_ASK);
   if(mMarketinfoMODE_ASK <= 0.0)  {
      printf("[%d]エラー ASKの取得失敗:：%s", __LINE__, DoubleToStr(mMarketinfoMODE_ASK));
      return false;
   }
   mMarketinfoMODE_BID = MarketInfo(global_Symbol,MODE_BID);
   if(mMarketinfoMODE_BID <= 0.0)  {
      printf("[%d]エラー BIDの取得失敗:：%s", __LINE__, DoubleToStr(mMarketinfoMODE_BID));
      return false;
   }

   int count = 0;
   // st_vOrders[]のうち、有効な取引の値で、かつ、決済されていない値を持つ要素を処理対象とする。
   // st_vOrders[]は途中、利用されなくなった項番が起こりうるので、最後st_vOrders[VTRADENUM_MAX-1]まで処理する。
   for(count = 0; count < VTRADENUM_MAX; count++) {
      if(st_vOrders[count].openTime <= 0) {
         break;
      }

      // v_flooringSLを適用しない仮想取引の場合は、以降の処理をしない。
      // 必要に応じて、このループ終了後に、個別の利確、損切値変更処理をする。
      // 例えば、引数が、"01FRAC"であれば、以降の処理を避けるため、trueを返す。
      // 【注記追加】20220622：01FRAC, 24ZZのように、チャートの動きから損切値（利確値）のみを設定する場合は、
      //                       外部パラメータTP,SLによらず、独自の損切値（利確値）を別途設定する。
      flag_avoid_v_update_AllOrdersTPSL = avoid_v_update_AllOrdersTPSL(st_vOrders[count].strategyID);
      if(flag_avoid_v_update_AllOrdersTPSL == true) {
         is_flag_avoid_v_update_AllOrdersTPSL  = true;
         continue;
      }
      // 約定日が意味のある値であり、決済日が設定されていない仮想取引を対象とする。
      if(st_vOrders[count].openTime > 0 && st_vOrders[count].closeTime <= 0)  {
         // 対象取引を選択する。
         mBUYSELL = st_vOrders[count].orderType;
         // 対象取引の属性値を取得する。
         if(mBUYSELL == OP_BUY || mBUYSELL == OP_SELL)  {
            mOrderTicket = st_vOrders[count].ticket;
            mOpen        = st_vOrders[count].openPrice;
            mSL_Order    = st_vOrders[count].orderStopLoss;
            mTP_Order    = st_vOrders[count].orderTakeProfit;
            mOrderLots   = st_vOrders[count].lots;
         }
         // 取引がロング、ショート以外は何もせず、次の候補を探す。
         else  {
            continue;
         }

         //
         // 決済値候補を計算する。
         //
         // ロングの場合
         if(mBUYSELL == OP_BUY) {
            // ロングの利確、損切候補値。
            // ロングの利益確定は、その時のASK＋ストップレベルより大きくなくてはならない。
            // ロングの損切は、その時のBID-ストップレベルより小さくなくてはならない。
            // 参考資料：https://toushi-strategy.com/mt4/stoplevel/
            if(mTP >= 0.0)  {
               mTP_BUY = NormalizeDouble(mOpen, global_Digits*2) + NormalizeDouble(mTP * mMarketinfoMODE_POINT, global_Digits*2); // 引数mTPから計算した利確の候補
               // mTP_BUYが、設定できない値であれば、0クリアする。= ロングの利確値は、ストップ値以下なら、0クリア
               if(mTP_BUY <= NormalizeDouble(mMarketinfoMODE_ASK, global_Digits*2) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits*2) ) {
                  mTP_BUY = 0.0;
               }
            }
            else {
               mTP_BUY = 0.0;
            }
            if(mSL >= 0.0)  {
               mSL_BUY = NormalizeDouble(mOpen, global_Digits*2) - NormalizeDouble(mSL * mMarketinfoMODE_POINT, global_Digits*2); // 引数mSLから計算した損切の候補
               if(mSL_BUY >=  NormalizeDouble(mMarketinfoMODE_BID, global_Digits*2) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits*2)) {
                  mSL_BUY = 0.0;
               }
               
            }
            else  {
               mSL_BUY = 0.0;
            }

            // ロング利確値の更新
            // ① st_vOrders[count].orderTakeProfitが未設定（0.0以下）の時は、利確値mTP_BUYが0.0でもそれ以外でも上書き。
            if(st_vOrders[count].orderTakeProfit <= 0.0) {
               st_vOrders[count].orderTakeProfit = mTP_BUY;
            }
            // ② st_vOrders[count].orderTakeProfitに設定値がある(0.0より大）の時は、変更しない。
            else {
               // 何もしない
            }
            // ロング損切値の更新
            // ① st_vOrders[count].orderTakeProfitが未設定（0.0以下）の時は、利確値mSL_BUYが0.0でもそれ以外でも上書き。
            if(st_vOrders[count].orderStopLoss <= 0.0) {
               st_vOrders[count].orderStopLoss = mSL_BUY;
            }
            // ② st_vOrders[count].orderStopLossに設定値がある(0.0より大）の時は、変更しない。
            else {
               // 何もしない
            }
         }
         // ショートの場合
         else if(mBUYSELL == OP_SELL) {
            // ショートの利益確定は、その時のBID-ストップレベルより小さくなくてはならない。
            // ショートの損切は、その時のASK+ストップレベルより大きくなくてはならない。
            // 参考資料：https://toushi-strategy.com/mt4/stoplevel/　　から、推測。
            if(mTP >= 0.0)  {
               mTP_SELL = NormalizeDouble(mOpen, global_Digits*2) - NormalizeDouble(mTP * mMarketinfoMODE_POINT, global_Digits*2); // 引数mTPから計算した利確の候補
               // mTP_SELLが、設定できない値であれば、0クリアする。= ショートの利確値は、ストップ値以上なら、0クリア
               if(mTP_SELL >= NormalizeDouble(mMarketinfoMODE_BID, global_Digits*2) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits*2) ) {
                  mTP_SELL = 0.0;
               }
            }
            else  {
               mTP_SELL = 0.0;
            }
            if(mSL >= 0.0)  {
               mSL_SELL = NormalizeDouble(mOpen, global_Digits*2) + NormalizeDouble(mSL * mMarketinfoMODE_POINT, global_Digits*2); // 引数mSLから計算した損切の候補
               
               // mSL_BUYが、設定できない値であれば、0クリアする。= ショートの損切値は、ストップ値以下なら、0クリア
               if(mSL_SELL <= NormalizeDouble(mMarketinfoMODE_ASK, global_Digits*2) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits*2) ) {
                  mSL_SELL = 0.0;
               }
               
            }
            else  {
               mSL_SELL = 0.0;
            }

            // ショート利確値の更新
            // ① st_vOrders[count].orderTakeProfitが未設定（0.0以下）の時は、利確値mTP_SELLが0.0でもそれ以外でも上書き。
            if(st_vOrders[count].orderTakeProfit <= 0.0) {
               st_vOrders[count].orderTakeProfit = mTP_SELL;
            }
            // ② st_vOrders[count].orderTakeProfitに設定値がある(0.0より大）の時は、変更しない。
            else {
               // 何もしない
            }
            // ショート損切値の更新
            // ① st_vOrders[count].orderTakeProfitが未設定（0.0以下）の時は、利確値mSL_SELLが0.0でもそれ以外でも上書き。
            if(st_vOrders[count].orderStopLoss <= 0.0) {
               st_vOrders[count].orderStopLoss = mSL_SELL;
            }
            // ② st_vOrders[count].orderStopLossに設定値がある(0.0より大）の時は、変更しない。
            else {
               // 何もしない
            }
         }
      }
   }            // for(count = 0; count < VTRADENUM_MAX; count++)

   //
   // avoid_v_update_AllOrdersTPSLで、他の戦略と同じ更新処理を拒否した場合の、
   // 仮想取引の戦略名などに応じた利確、損切更新処理
   // 20220622 損切値が有利な場合に上書き設定することに変更
   // 
   if(is_flag_avoid_v_update_AllOrdersTPSL == true) {
      // FRACで登録した仮想取引の損切更新。
      // 実行時点のフラクタルを取得し、有利であれば損切値を更新する。
      update_v_AllOrdersSLFrac(global_Symbol, 
                               g_StratName01);

      // ZIGZAGで登録した仮想取引の損切更新。
      // 損切値の候補がより有利であれば、上書きする。
      // 損切値の候補は、
      // 2つ前の谷より直前の谷が高ければ、ロングのストップを直前の谷に更新する。
      // 2つ前の山より直前の山が低ければ、ショートのストップを直前の山に更新する。
      double   local_ZigTop[5];     //ジグザグの山保存用。ZigTop[0]は最新の高値、ZigTop[1]は1つ前の高値。
      datetime local_ZigTopTime[5]; //ジグザグの山の時間。
      double   local_ZigBottom[5];  //ジグザグの谷保存用
      datetime local_ZigBottomTime[5];  //ジグザグの谷保存用   
      double   local_LastMountORBottom = get_ZigZagCOPY(1, 
                                                        ZigzagDepth,
                                                        ZigzagDeviation,
                                                        ZigzagBackstep,   
                                                        local_ZigTop,
                                                        local_ZigTopTime,
                                                        local_ZigBottom,
                                                        local_ZigBottomTime
                                                        );
      update_v_AllOrdersSLZigzag(g_StratName24, global_Symbol,
                                 local_LastMountORBottom,
                                 local_ZigTop,
                                 local_ZigBottom
                                 );
   }                              

   return true;  //
}//全オーダーの指値と逆指値が設定されていることをチェックする。


/* get_ZigZagCOPYは、Puer_ZZ.mqhのget_ZigZagのコピー
　　　この関数のためだけにPuer_ZZ.mqhをincludeし、その結果、不要な外部パラメーター宣言も引き継ぐことを避けるため、
　　　コピーを作成した。
*/
// Zigzagの山と谷の値を引数で返すバージョン
// グローバル変数への結果セットはしないことに注意
int get_ZigZagCOPY(int mShift,
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
   
   for(i = mShift; i <= mShift + 200; i++) {  // 200は、感覚的な値。200シフト前から計算すれば、結果が出る予想。
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
//| Fracでも、Zigzagに似せた損切値更新ロジックを使う。
//| 仮想取引向け。                                        |
//| ・取引が持つ損切値より有利であれば更新する。
//| ・2つ前の谷より直前の谷が高ければ、ロングのストップを直前の谷に更新する。                         |
//| ・2つ前の山より直前の山が低ければ、ショートのストップを直前の山に更新する。                        |
//|  ただし、以下を前提とする                                                        |
//|  ロングエントリー                                                               |
//|  ・エントリー直後(損切値が0.0)に、直前の谷をストップとする。                                  |
//|   ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、直近の値とする。 |
//|  ショートエントリー                                                              |
//|  ・エントリー直後(損切値が0.0)に、直前の山をストップとする。                                |
//|   ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、直近の値とする。|
//|                                                                         |
//|入力：通貨ペア、戦略名、フラクタルの山を直近２つ、谷を直近２つ。。                                                    | 
//|出力：1件でも失敗すれば、falseを返す。                                              |
//--------------------------------------------------------------------------+

void update_v_AllOrdersSLFrac(string mSymbol, 
                              string mStrategy) {
   // 仮想取引の値を更新するためにこの関数が呼ばれた時点の
   // フラクタルの値を取得し、構造体st_Fractalsに入れる。
   st_Fractal m_st_Fractals[FRAC_NUMBER];
   bool flag_getFrac = get_Fractals(m_st_Fractals);
   if(flag_getFrac == false) {
      return ;
   }
   
   update_v_AllOrdersSLFrac(mSymbol,      // 更新対象とする仮想取引の通貨ペア
                            mStrategy,    // 更新対象とする仮想取引の戦略名
                            m_st_Fractals // 更新時点のフラクタル値
                            );
}


bool update_v_AllOrdersSLFrac(string mSymbol,           // 更新対象とする仮想取引の通貨ペア
                              string mStrategy,          // 更新対象とする仮想取引の戦略名
                              st_Fractal &m_st_Fractals[] // 更新時点のフラクタル値
                              ) {
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
                              
   int i = 0;
   bool ret = true;
   double long_SL_Cand  = 0.0; // ロングの損切値候補
   double short_SL_Cand = 0.0; // ショートの損切値候補
   int mFlag = -1;             // OederModifyの返り値

   
   bool flag_getFrac = get_Fractals(m_st_Fractals);
   if(flag_getFrac == false) {
      return false;
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

   int LastMountORBottom = FRAC_NONE; // 直近がフラクタルの山FRAC_MOUNTか谷FRAC_BOTTOMか。
   if(mFractals_UPPER1_time > mFractals_LOWER1_time && mFractals_LOWER1_time > 0) { //山の方が、先日付
      LastMountORBottom = FRAC_MOUNT;
   }
   else if(mFractals_UPPER1_time < mFractals_LOWER1_time && mFractals_UPPER1_time > 0) { //山の方が、先日付
      LastMountORBottom = FRAC_BOTTOM;
   }
   else {
      LastMountORBottom = FRAC_NONE;
       printf( "[%d]VT FRACの直前の山と谷を判断できない。　UPPER1=%s-%s UPPER2=%s-%s LOWER1=%s-%s  LOWER2=%s-%s" , __LINE__,
               TimeToStr(mFractals_UPPER1_time), DoubleToStr(mFractals_UPPER1_y, global_Digits),
               TimeToStr(mFractals_UPPER2_time), DoubleToStr(mFractals_UPPER2_y, global_Digits),
               TimeToStr(mFractals_LOWER1_time), DoubleToStr(mFractals_LOWER1_y, global_Digits),
               TimeToStr(mFractals_LOWER2_time), DoubleToStr(mFractals_LOWER2_y, global_Digits)
      );

      return false;
   }   
 
   // 直近がFracの谷であれば、ロングの損切値候補を計算する。
   // ただし、2つ前の谷より直前の谷が高いのみ、ロングのストップを直前の谷に更新する。
   if( (LastMountORBottom == FRAC_BOTTOM) 
        && (NormalizeDouble(mFractals_LOWER1_y, global_Digits) > NormalizeDouble(mFractals_LOWER2_y, global_Digits) && mFractals_LOWER2_y > 0.0)) {
         long_SL_Cand = mFractals_LOWER1_y;
   }
   // 直近がFracの山であれば、ショートの損切値候補を計算する。
   // ただし、2つ前の山より直前の山が低い場合とし、直前の山の値を候補とする。 
   else if( (LastMountORBottom == FRAC_MOUNT)
             && (NormalizeDouble(mFractals_UPPER1_y, global_Digits) < NormalizeDouble(mFractals_UPPER2_y, global_Digits) && mFractals_UPPER1_y > 0.0)) {
         short_SL_Cand = mFractals_UPPER1_y;
   }
   else {
      ret = false;
   }

   if(long_SL_Cand <= 0.0 && short_SL_Cand <= 0.0) {
      ret = false;   
   }
   // この手前までに問題が発生していたら、以降の処理は行わない。
   if(ret == false) {
      return ret;
   }

   // 口座情報を取得する。
   double mMarketinfoMODE_ASK       = MarketInfo(mSymbol,MODE_ASK);
   double mMarketinfoMODE_BID       = MarketInfo(mSymbol,MODE_BID);
   double mMarketinfoMODE_POINT     = global_Points;
   double mMarketinfoMODE_STOPLEVEL = global_StopLevel;

// 事前に直前の山や谷を損切値候補に設定している。
// long_SL_Cand = Fractals_LOWER1_y;
// short_SL_Cand = Fractals_UPPER1_y;
 
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }
     
      if(st_vOrders[i].openTime > 0 && st_vOrders[i].closeTime <= 0)  {
         if( StringLen(st_vOrders[i].strategyID) > 0 && StringLen(mStrategy) > 0 && StringCompare(st_vOrders[i].strategyID, mStrategy) == 0) {
            if( StringLen(st_vOrders[i].symbol) > 0  && StringLen(mStrategy) > 0 && StringCompare(st_vOrders[i].symbol, mSymbol) == 0) {
               int    mTicket          = st_vOrders[i].ticket;
               double mOpen            = st_vOrders[i].openPrice;
               double mOrderStopLoss   = st_vOrders[i].orderStopLoss;
               double mOrderTakeProfit = st_vOrders[i].orderTakeProfit;
               int    mBuySell         = st_vOrders[i].orderType;
              
               // ロングの場合の損切更新
               if(mBuySell == OP_BUY) {
                  // 注目しているOrderが、エントリー直後(損切値が0.0)の時は、
                  // ・エントリー直後(損切値が0.0)に、直前の谷をストップとする。 
                  // ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、
                  // 損切値が設定されないまま、含み損が広がり続けるのを防ぐため、直近の値とする。 
                  if(mOrderStopLoss <= 0.0) {
                     if(long_SL_Cand > 0.0 && NormalizeDouble(long_SL_Cand, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // 損切値の更新は、より有利になる場合限定する。
                        if(NormalizeDouble(mOrderStopLoss, global_Digits) < NormalizeDouble(long_SL_Cand, global_Digits)) {
                           st_vOrders[i].orderStopLoss = long_SL_Cand;
                        }
                     }
                     else {
                        // long_SL_Candが制約により設定できないため、制約を満たす直近の谷を探す。
                        double buf_long_SL_Cand = NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble((1+mMarketinfoMODE_STOPLEVEL) * mMarketinfoMODE_POINT, global_Digits);
                        buf_long_SL_Cand = get_Next_Lower_FRAC(global_Symbol,     // 通貨ペア
                                                               global_Period,     // タイムフレーム 
                                                               mFractals_LOWER1_x, // このシフト＋１以上のシフトでFractalを計算する。
                                                               buf_long_SL_Cand   // この値より小さな値を探す
                                                               );
                        if(buf_long_SL_Cand > DOUBLE_VALUE_MIN) {
                           // 設定可能な次の谷を見つけた。
                           // 損切値の更新は、より有利になる場合限定する。
                           if(NormalizeDouble(mOrderStopLoss, global_Digits) < NormalizeDouble(buf_long_SL_Cand, global_Digits)) {
                              st_vOrders[i].orderStopLoss = buf_long_SL_Cand;
                           }

                        }
                        // 制約を満たす直近の谷も見つからなければ、損切値設定をあきらめる
                        else {
                          // 設定可能な最小値を損切値に設定していたが、性能が悪すぎた。
                          // 谷から計算される損切値以外は設定しない。
                        }
                     }
                  }
                  else if(mOrderStopLoss > 0.0 
                          && long_SL_Cand  > 0.0  
                          // 損切値が設定されていれば、候補値の方が損失が少なくなる時に更新する。ただし、制約あり。
                          && NormalizeDouble(long_SL_Cand, global_Digits) > NormalizeDouble(mOrderStopLoss, global_Digits) 
                         )  {
                     if(long_SL_Cand < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // 損切値の更新は、より有利になる場合限定する。
                        if(NormalizeDouble(mOrderStopLoss, global_Digits) < NormalizeDouble(long_SL_Cand, global_Digits)) {
                           st_vOrders[i].orderStopLoss = long_SL_Cand;
                        }
                     }
                     else {
                        // 損切値の初回設定時と異なり、制約を受けて更新できない時は、何もしない。
                     }
                  }
               }
               // ショートの場合の損切更新
               else if(mBuySell == OP_SELL) {
                  // 注目しているOrderが、エントリー直後(損切値が0.0)の時は、
                  // ・エントリー直後(損切値が0.0)に、直前の山をストップとする。 
                  // ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の山を使えない場合は、直近の値とする。 
                  if(mOrderStopLoss <= 0.0) {
                     // 冒頭で、2つ前の谷より直前の谷が高い場合のみ、ロングのストップを直前の谷を更新候補long_SL_Candにしていれば、その値を設定できるか調べる。
                     if(short_SL_Cand > 0.0 && NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // 損切値の更新は、より有利になる場合限定する。
                        if(NormalizeDouble(mOrderStopLoss, global_Digits) > NormalizeDouble(short_SL_Cand, global_Digits)) {
                           st_vOrders[i].orderStopLoss = short_SL_Cand;
                        }
                        else if(NormalizeDouble(mOrderStopLoss, global_Digits) <= 0.0) {
                           st_vOrders[i].orderStopLoss = short_SL_Cand;                        
                        }
                     }
                     else {
                         // short_SL_Candが制約により設定できないため、制約を満たす直近の山を探す。
                         double buf_short_SL_Cand = NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble((1+mMarketinfoMODE_STOPLEVEL) * mMarketinfoMODE_POINT, global_Digits);
                         buf_short_SL_Cand = get_Next_Upper_FRAC(global_Symbol,     // 通貨ペア
                                                                 global_Period,     // タイムフレーム 
                                                                 mFractals_UPPER1_x, // このシフト＋１以上のシフトでFractalを計算する。
                                                                 buf_short_SL_Cand  // この値より小さな値を探す
                                                               );
                         if(buf_short_SL_Cand > DOUBLE_VALUE_MIN) {
                           // 設定可能な次の山を見つけた。
                           // 損切値の更新は、より有利になる場合限定する。
                           if(NormalizeDouble(mOrderStopLoss, global_Digits) > NormalizeDouble(buf_short_SL_Cand, global_Digits)) {
                              st_vOrders[i].orderStopLoss = buf_short_SL_Cand;
                           }
                           else if(NormalizeDouble(mOrderStopLoss, global_Digits) <= 0.0) {
                              st_vOrders[i].orderStopLoss = short_SL_Cand;                        
                           }                           
                         }
                        // 制約を満たす直近の山も見つからなければ、損切値設定をあきらめる
                        else {
                           printf( "[%d]VTエラー 仮想取引・ショートの初回損切値を設定できず。" , __LINE__);
                        }
                     }
                  }
                  else if(mOrderStopLoss > 0.0 
                          && short_SL_Cand > 0.0   
                          // 損切値が設定されていれば、候補値の方が損失が少なくなる時に設定する。
                          && NormalizeDouble(short_SL_Cand, global_Digits) < NormalizeDouble(mOrderStopLoss, global_Digits) 
                          ) {
                     if(short_SL_Cand > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // 損切値の更新は、より有利になる場合限定する。
                        if(NormalizeDouble(mOrderStopLoss, global_Digits) > NormalizeDouble(short_SL_Cand, global_Digits)) {
                           st_vOrders[i].orderStopLoss = short_SL_Cand;
                        }
                        else if(NormalizeDouble(mOrderStopLoss, global_Digits) <= 0.0) {
                           st_vOrders[i].orderStopLoss = short_SL_Cand;                        
                        }                        
                     }
                     else {
                        // 損切値の初回設定時と異なり、制約を受けて更新できない時は、何もしない。
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

//+------------------------------------------------------------------+
//| 仮想取引の損切を更新する                     　　　              |
//| ※MODE_ASK、MODE_BIDを使っていることから、過去日付では使えない。 |
//+------------------------------------------------------------------+
bool v_flooringSL(double mPips)  {
   int mOrderTicket = 0;
   double mSL     = 0.0;
   double mTP     = 0.0;
   int mBUYSELL   = 0;
   double minSL   = 0.0;
   double mOpen   = 0.0;
   double mClose  = 0.0;
   int mFlag      = 0;
   string mSymbol = "";
   bool ret = true;

   // mPipsが負は想定していない。
   if(mPips < 0.0)  {
      return false;
   }

   int count = 0;
   double mMarketinfoMODE_ASK       = 0.0;
   double mMarketinfoMODE_BID       = 0.0;
   double mMarketinfoMODE_POINT     = 0.0;
   double mMarketinfoMODE_STOPLEVEL = 0.0;

   // 次の値を使わないケースもあるが、for文内で繰り返し実行するデメリットを避けるため、事前に取得することとした。
   mMarketinfoMODE_ASK       = MarketInfo(mSymbol,MODE_ASK);
   mMarketinfoMODE_BID       = MarketInfo(mSymbol,MODE_BID);
   mMarketinfoMODE_POINT     = MarketInfo(mSymbol,MODE_POINT);
   mMarketinfoMODE_STOPLEVEL = MarketInfo(mSymbol,MODE_STOPLEVEL);
   
   for(count = 0; count < VTRADENUM_MAX; count++) {
      // st_vOrdersのうち、有効な取引の値で、かつ、決済されていない値を持つ要素を処理対象とする。
      if(st_vOrders[count].openTime <= 0) {
         break;
      }

      if(st_vOrders[count].openTime > 0 && st_vOrders[count].closeTime <= 0)  {
      
         // v_flooringSLを適用しない仮想取引の場合は、以降の処理をしない。
         bool flagAvoid = avoid_v_flooringSL(st_vOrders[count].strategyID);
         if(flagAvoid == true) {
            continue;
         }
         
         if(mBUYSELL == OP_BUY || mBUYSELL == OP_SELL)  {
            mOrderTicket = st_vOrders[count].ticket;
            mBUYSELL     = st_vOrders[count].orderType;
            mSL          = st_vOrders[count].orderStopLoss;
            mTP          = st_vOrders[count].orderTakeProfit;
            mOpen        = st_vOrders[count].openPrice;
            mSymbol      = st_vOrders[count].symbol;
         }
         

         double tp        = 0.0;
         double sl        = 0.0;
         double bufSL     = 0.0;
         double minimalSL = 0.0;
         double maxmalSL  = 0.0;

         // ロングの場合
         if(mBUYSELL == OP_BUY)  {
            bufSL = NormalizeDouble(mOpen, global_Digits) + NormalizeDouble(change_PiPS2Point(mPips), global_Digits); // 引数を使ったロングの損切候補
            // ロングの損切は、その時のBID-ストップレベルより小さくなくてはならない。
            // 参考資料：https://toushi-strategy.com/mt4/stoplevel/
            maxmalSL = NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL, global_Digits);

            // 損切候補bufSLが、取りうる最大値maxmalSLより小さく、設定済み損切値より大きければ、
            // 値を変更する。
            if(NormalizeDouble(bufSL, global_Digits) < NormalizeDouble(maxmalSL, global_Digits)
               && NormalizeDouble(bufSL, global_Digits) > NormalizeDouble(mSL, global_Digits))  {
               st_vOrders[count].orderStopLoss = NormalizeDouble(bufSL, global_Digits);
            }
         }

         // ショートの場合
         else if(mBUYSELL == OP_SELL)  {
               bufSL = NormalizeDouble(mOpen, global_Digits) - NormalizeDouble(change_PiPS2Point(mPips), global_Digits); // 引数を使ったショートの損切候補
               // ショートの損切は、その時のASK+ストップレベルより大きくなくてはならない。
               // 参考資料：https://toushi-strategy.com/mt4/stoplevel/　　から、推測。
               minimalSL = NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL, global_Digits) ;

               // 損切候補bufSLが、取りうる最小値minimalSLより大きく、設定済み損切値より小さければ、
               // 値を変更する。
               if(NormalizeDouble(bufSL, global_Digits) > NormalizeDouble(minimalSL, global_Digits)
                  && NormalizeDouble(bufSL, global_Digits) < NormalizeDouble(mSL,global_Digits))  {
                  st_vOrders[count].orderStopLoss = NormalizeDouble(bufSL, global_Digits);
               }
         }
         // ロングでもショートでもない場合
         else  {
         }
      }
   }
   return ret;
}






//+------------------------------------------------------------------+
//| 仮想取引の決済をする（決済価格と時間を引数渡しする場合）         |
//+------------------------------------------------------------------+
// 指定したPIPS数の利益確定又は損切を行う。
// 仮想取引st_vOrdersのメンバーのうち、Closeしていない＆openTime = mSettleTimeを決済対象に追加。
// 決済判断にmMarketinfoMODE_BIDやmMarketinfoMODE_ASKではなく、引数mSettlePriceを使う。
// 【注意】約定日がmSettleTime以前の仮想取引を決済対象とするため、mSettleTimeは過去日付から行う必要がある。
//
//
//
//
//
// 【保留】直前のv_do_ForcedSettlement実行時間をグローバル変数に持っておく。
//       PERIOD_M1の直近の足から、直前の実行時間までさかのぼりながら、決済可能かどうかを判断する。
//
//

datetime v_history_timeDT[1440]; // 時刻。datetime表記
string   v_history_timeSTR[1440];// 時刻。文字列表記
double   v_history_open[1440];   // 直前1440シフト分の始値。1440は1日1440分から決定
double   v_history_high[1440];   // 直前1440シフト分の高値。1440は1日1440分から決定
double   v_history_low[1440];    // 直前1440シフト分の安値。1440は1日1440分から決定
double   v_history_close[1440];  // 直前1440シフト分の終値。1440は1日1440分から決定
st_vOrderPL buf2_st_vOrderPLs[VOPTPARAMSNUM_MAX];
bool v_do_ForcedSettlement(datetime mSettleTime, double mSettlePrice, string mSymbol, int mTP, int mSL)  {

   bool flag_read_historyData = false; // read_historyDataを実行したらtrue
   if(mSettlePrice <= 0.0) {
      return false;
   }

   
   // 前回の強制決済時lastForceSettlementTime以降から、現時点TimeCurrent()までの間の
   // １分足4値を取得する。最大で1440シフト前までの値を取得する。
   // 前回データ取得シフトと今回データ取得シフトが同じ場合は、読み返しはしない

   if(mSettleTime == lastForceSettlementTime) {
      return false;
   }
   else {
   }
   
   int count = 0;
   for(count = 0; count < VTRADENUM_MAX; count++)  {
      // 空欄に到達したら、処理を中断する。
      if(st_vOrders[count].openTime <= 0) {
     
         break;
      }

      // st_vOrdersのうち、有効な取引の値で、かつ、決済されていない値を持つ要素を処理対象とする。
      if(st_vOrders[count].openTime > 0
         && st_vOrders[count].closeTime <= 0 
         && (StringLen(st_vOrders[count].symbol) > 0 && StringLen(mSymbol) > 0 && StringCompare(st_vOrders[count].symbol, mSymbol) == 0)
         && st_vOrders[count].openTime < mSettleTime)  {
      
         // 処理対象とする仮想取引が１件以上あったときに１度だけread_historyDataを実行する。
         if(flag_read_historyData == false) {
         
            read_historyData(mSettleTime,  // データを取得する開始日時  
                             lastForceSettlementTime // データを取得する終了日時。ただし、最大でも1440シフトまで
                             );
            flag_read_historyData = true;
         }

         double mOpen       = st_vOrders[count].openPrice;
         int    mBuySell    = st_vOrders[count].orderType;
         double mTakeProfit = NormalizeDouble(st_vOrders[count].orderTakeProfit, global_Digits);
         double mStopLoss   = NormalizeDouble(st_vOrders[count].orderStopLoss, global_Digits);

         // 仮想取引は、自動的に利確、損切がされないため、強制決済は必要。
         // しかし、ZZやFRACのように外部パラメータTPやSLを使った強制決済をしない戦略もある
         // 強制損切対象外の時は、avoid_v_do_ForcedSettlementが強制決済は実行しないFRACやZZの時、true
         bool flag_avoid_v_do_ForcedSettlement = avoid_v_do_ForcedSettlement(st_vOrders[count].strategyID);

         // ロングの場合の利確、損切
         // １分足4値と、売買区分、利確値、損切値、TP、SLを使って、決済日時と決済金額、決済損益を計算する。
         datetime settleTime;  // 決済時刻
         double   settlePrice; // 決済価格
         double   settlePL;    // 決済損益PIPS
         bool flag_calc_Settlement;
         
         if(mBuySell == OP_BUY)  {
            double mMarketinfoMODE_BID = mSettlePrice;  // 引数で渡された決済用価格を使う。
            
            //　決済条件を満たすかどうかによらず、評価損益を更新する。
            st_vOrders[count].estimatePL    = change_Point2PIPS(NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(st_vOrders[count].openPrice, global_Digits)) ;
            st_vOrders[count].estimatePrice = NormalizeDouble(mMarketinfoMODE_BID, global_Digits);
            st_vOrders[count].estimateTime  = mSettleTime;

            // 独自の決済をする取引は以下を行わない。
            if(flag_avoid_v_do_ForcedSettlement == true) {
               continue;
            }

            // １分足4値と、売買区分、利確値、損切値、TP、SLを使って、決済日時と決済金額、決済損益を計算する。
            flag_calc_Settlement =
            calc_Settlement(st_vOrders[count].strategyID, 
                            mBuySell, // 売買区分
                            st_vOrders[count].openTime, // 約定日
                            st_vOrders[count].openPrice, // 約定値
                            st_vOrders[count].orderTakeProfit, // 利確値
                            st_vOrders[count].orderStopLoss,   // 損切値
                            mTP, // 利確PIPS
                            mSL, // 損切PIPS
                            settleTime, // 出力：決済日時
                            settlePrice,// 出力：決済価格
                            settlePL    // 出力：決済損益
                            );

            if(flag_calc_Settlement == true) {
               st_vOrders[count].closeTime  = settleTime;
               st_vOrders[count].closePrice = NormalizeDouble(settlePrice, global_Digits);
               st_vOrders[count].closePL    = NormalizeDouble(settlePL, global_Digits) ;
            }
            else {
            }
         }
         // ロングの場合の利確、損切は、ここまで。
         //　ショートの場合の利確、損切
         else if(mBuySell == OP_SELL)  {
               double mMarketinfoMODE_ASK = mSettlePrice;  // 引数で渡された決済用価格を使う。
               //　決済条件を満たすかどうかによらず、評価損益を更新する。決済時は、0クリアする。
               st_vOrders[count].estimatePL    = (NormalizeDouble(mOpen, global_Digits) - NormalizeDouble(mMarketinfoMODE_ASK, global_Digits)) / global_Points;
               st_vOrders[count].estimatePrice = NormalizeDouble(mMarketinfoMODE_ASK, global_Digits);
               st_vOrders[count].estimateTime  = mSettleTime;

               // 独自の決済をする取引は以下を行わない。
               if(flag_avoid_v_do_ForcedSettlement == true) {
                  continue;
               }
               // １分足4値と、売買区分、利確値、損切値、TP、SLを使って、決済日時と決済金額、決済損益を計算する。
               flag_calc_Settlement =
               calc_Settlement(st_vOrders[count].strategyID, 
                               mBuySell, // 売買区分
                               st_vOrders[count].openTime, // 約定値
                               st_vOrders[count].openPrice, // 約定値
                               st_vOrders[count].orderTakeProfit, // 利確値
                               st_vOrders[count].orderStopLoss,   // 損切値
                               mTP, // 利確PIPS
                               mSL, // 損切PIPS
                               settleTime, // 出力：決済日時
                               settlePrice,// 出力：決済価格
                               settlePL    // 出力：決済損益
                               );
                if(flag_calc_Settlement == true) {
                
                  st_vOrders[count].closeTime  = settleTime;
                  st_vOrders[count].closePrice = NormalizeDouble(settlePrice, global_Digits);
                  st_vOrders[count].closePL    = NormalizeDouble(settlePL, global_Digits);

               }
               else {
               }
         }
      }
   }
      
   lastForceSettlementTime = mSettleTime;
  
   return true;
}

bool get_NearestMinutesShift(datetime mTarget, int &mShift) {
   int i;
   int nearestBiggerShift = -1; //mTargetを超える最小のシフト
   mShift = -1;
   for(i = 0; i < 10000; i++) {
      datetime currDT = iTime(global_Symbol, PERIOD_M1, i);
      
      if(mTarget == currDT){

         mShift = i;
         return true;
      }
      else if(mTarget < currDT) {
         nearestBiggerShift = i;
      } 
      else {
      
         mShift = nearestBiggerShift;
         return true;
      }
   }
   
   return false;
}

bool read_historyData(datetime mStartDT,  // データを取得する開始日時。比較して未来日付。強制決済をする日時。
                      datetime mEndDT     // データを取得する終了日時。ただし、最大でも1440シフトまで。比較して過去日付。前回強制決済をした日付。
                    ) {

   int startShift = iBarShift(global_Symbol, 1, mStartDT,false);
   int endShift = iBarShift(global_Symbol, 1, mEndDT,false);
   
   if(startShift < 0) {
      return false;
   }

   if(endShift < startShift) {
      return false;
   }
  
   if(endShift - startShift > 1440) {
      endShift = startShift + 1440;
   }

   ArrayInitialize(v_history_timeDT, INT_VALUE_MIN);
   ArrayInitialize(v_history_open  , 0.0);
   ArrayInitialize(v_history_high  , 0.0);   
   ArrayInitialize(v_history_low   , 0.0);   
   ArrayInitialize(v_history_close , 0.0);
   int i;
   int count = 0;
   for(i = startShift; i <= endShift; i++) {
      v_history_timeDT[count]  = iTime(global_Symbol, PERIOD_M1, i); // 時刻。datetime表記
      v_history_timeSTR[count] = TimeToStr(v_history_timeDT[count]); // 時刻。文字列表記
      v_history_open[count]    = iOpen(global_Symbol, PERIOD_M1, i); // 直前1440シフト分の始値。1440は1日1440分から決定
      v_history_high[count]    = iHigh(global_Symbol, PERIOD_M1, i); // 直前1440シフト分の高値。1440は1日1440分から決定
      v_history_low[count]     = iLow(global_Symbol, PERIOD_M1, i);  // 直前1440シフト分の安値。1440は1日1440分から決定
      v_history_close[count]   = iClose(global_Symbol, PERIOD_M1, i);// 直前1440シフト分の終値。1440は1日1440分から決定   

      count++;
   }
   return true;
}                    
//
// 事前に取得済みの4値を使い、決済時刻と価格、損益を計算する。
// 1分足データを使うが、利確と損切の判断がつかない場合は、損切を優先させる
// 決済されればtrue。決済されなければfalseを返す。
//
// 【前提】４値が更新されていること。
// datetime v_history_timeDT[1440]; // 時刻。datetime表記
// string   v_history_timeSTR[1440];// 時刻。文字列表記
// double   v_history_open[1440];   // 直前1440シフト分の始値。1440は1日1440分から決定
// double   v_history_high[1440];   // 直前1440シフト分の高値。1440は1日1440分から決定
// double   v_history_low[1440];    // 直前1440シフト分の安値。1440は1日1440分から決定
// double   v_history_close[1440];  // 直前1440シフト分の終値。1440は1日1440分から決定
bool  calc_Settlement(string mStrategy, // 戦略名（参考情報）
                      int mBuySell, // 売買区分
                      datetime mopenTime, // 約定日時
                      double mopenPrice, // 約定値
                      double morderTakeProfit, // 利確値
                      double morderStopLoss,   // 損切値
                      double mTP, // 利確PIPS
                      double mSL, // 損切PIPS
                      datetime &msettleTime, // 出力：決済日時
                      double   &msettlePrice,// 出力：決済価格
                      double   &msettlePL    // 出力：決済損益
                      ) {
   
   // 返り値を初期化する。
   msettleTime  = 0;
   msettlePrice = 0.0;
   msettlePL    = 0.0;

   // 利確値morderTakeProfitが指定されていなければ、利確PIPSを使って更新する。
   if(morderTakeProfit <= 0.0) {
      if(mBuySell == OP_BUY) {
         morderTakeProfit = NormalizeDouble(mopenPrice, global_Digits) + NormalizeDouble(change_PiPS2Point(mTP), global_Digits);
      }
      else if(mBuySell == OP_SELL) {
         morderTakeProfit = NormalizeDouble(mopenPrice, global_Digits) - NormalizeDouble(change_PiPS2Point(mTP), global_Digits);
      }
   }

   // 損切値morderStopLossが指定されていなければ、損切PIPSを使って更新する。
   if(morderStopLoss <= 0.0) {
      if(mBuySell == OP_BUY) {
         morderStopLoss = NormalizeDouble(mopenPrice, global_Digits) - NormalizeDouble(change_PiPS2Point(mTP), global_Digits);
      }
      else if(mBuySell == OP_SELL) {
         morderStopLoss = NormalizeDouble(mopenPrice, global_Digits) + NormalizeDouble(change_PiPS2Point(mTP), global_Digits);
      }
   }
   // 直近の４値から順に決済できるタイミングを探す。
   int i;
   bool doneSettle = false;
   double donePrice;

   // 直近の４値が入ったヒストリーデータv_history_*[0]は一番未来、v_history_*[n]は一番過去のため、
   // 直近のうち一番過去のv_history_*[n]から決済できるタイミングを探すこと。

   // ヒストリーデータがいくつあるかを計算する。
   int v_history_LAST_INDEX = -1; // ヒストリーデータが配列の何番目まで値を持つか。
   for(i = 0; i < 1440; i++) {
      if(v_history_timeDT[i] <= 0) {
         break;
      }
      v_history_LAST_INDEX = i;
   }
   if(v_history_LAST_INDEX < 0) {
      return false; // 決済用ヒストリーデータが無いため、決済は発生せず、falseを返す。
   }
   
   for(i = v_history_LAST_INDEX; i >= 0; i--) {
      if(v_history_timeDT[i] <= mopenTime) {
         continue;
      }
      doneSettle = false;
      donePrice = 0.0;


      //
      // ロングの場合
      //
      if(mBuySell == OP_BUY) {
         // openで決済できるかを判断する
         // 損切発生
         if( NormalizeDouble(v_history_open[i], global_Digits) <= NormalizeDouble(morderStopLoss, global_Digits) ) {
            doneSettle = true;
            donePrice =  NormalizeDouble(morderStopLoss, global_Digits);
         }
         // 利確発生
         else if(NormalizeDouble(v_history_open[i], global_Digits) >= NormalizeDouble(morderTakeProfit, global_Digits) ) {
            doneSettle = true;
            donePrice =  NormalizeDouble(morderTakeProfit, global_Digits);
         }
      
         // lowで決済できるかを判断する。
         // 損切発生      
         else if(NormalizeDouble(v_history_low[i], global_Digits) <= NormalizeDouble(morderStopLoss, global_Digits) ) {
            doneSettle = true;
            donePrice =  NormalizeDouble(morderStopLoss, global_Digits);
         }
         // 利確は発生しえない。＝発生するとしたら、openとlowが同じ値であり、既に検討済み
      
         // highで決済できるかを判断する。
         // 利確発生
         else if(NormalizeDouble(v_history_high[i], global_Digits) >= NormalizeDouble(morderTakeProfit, global_Digits) ) {
            doneSettle = true;
            donePrice =  NormalizeDouble(morderTakeProfit, global_Digits);
         }
         // 損切は発生しえない。＝発生するとしたら、openとhighが同じ値であり、既に検討済み
      
         // (例外のため）closeで決済できるかを判断する。
         // 損切発生
         else if( NormalizeDouble(v_history_close[i], global_Digits) <= NormalizeDouble(morderStopLoss, global_Digits) ) {
            doneSettle = true;
            donePrice =  NormalizeDouble(morderStopLoss, global_Digits);
         }
         // 利確発生
         else if(NormalizeDouble(v_history_close[i], global_Digits) >= NormalizeDouble(morderTakeProfit, global_Digits) ) {
            doneSettle = true;
            donePrice =  NormalizeDouble(morderTakeProfit, global_Digits);
         }
      
         // 決済可能doneSettle=trueであれば、返り値をセットして、return falseする。
         if(doneSettle == true) {
            msettleTime  = v_history_timeDT[i]; // 出力：決済日時
            msettlePrice = donePrice;       // 出力：決済価格
            msettlePL    = NormalizeDouble( (donePrice - mopenPrice) / global_Points, global_Digits);   // 出力：決済損益
            break;
         }
      }  // ロングの場合、ここまで
      
      
      //
      // ショートの場合
      //
      else if(mBuySell == OP_SELL) {
         donePrice = 0.0;
         // openで決済できるかを判断する
         // 損切発生
         if( NormalizeDouble(v_history_open[i], global_Digits) >= NormalizeDouble(morderStopLoss, global_Digits) ) {
            doneSettle = true;
            donePrice =  NormalizeDouble(morderStopLoss, global_Digits);
         }
         // 利確発生
         else if(NormalizeDouble(v_history_open[i], global_Digits) <= NormalizeDouble(morderTakeProfit, global_Digits) ) {
            doneSettle = true;
            donePrice =  NormalizeDouble(morderTakeProfit, global_Digits);
         }
      
         // highで決済できるかを判断する。
         // 損切発生
         else if(NormalizeDouble(v_history_high[i], global_Digits) >= NormalizeDouble(morderStopLoss, global_Digits) ) {
            doneSettle = true;
            donePrice =  NormalizeDouble(morderStopLoss, global_Digits);
         }
         // 利確は発生しえない。＝発生するとしたら、openとlowが同じ値であり、既に検討済み

         // lowで決済できるかを判断する。
         // 利確発生      
         else if(NormalizeDouble(v_history_low[i], global_Digits) <= NormalizeDouble(morderTakeProfit, global_Digits) ) {
            doneSettle = true;
            donePrice =  NormalizeDouble(morderTakeProfit, global_Digits);
         }
         // 利確は発生しえない。＝発生するとしたら、openとlowが同じ値であり、既に検討済み
      
      
         // (例外のため）closeで決済できるかを判断する。
         // 損切発生
         else if( NormalizeDouble(v_history_close[i], global_Digits) >= NormalizeDouble(morderStopLoss, global_Digits) ) {
            doneSettle = true;
            donePrice =  NormalizeDouble(morderStopLoss, global_Digits);
         }
         // 利確発生
         else if(NormalizeDouble(v_history_close[i], global_Digits) <= NormalizeDouble(morderTakeProfit, global_Digits) ) {
            doneSettle = true;
            donePrice =  NormalizeDouble(morderTakeProfit, global_Digits);
         }
      
         // 決済可能doneSettle=trueであれば、返り値をセットして、return falseする。
         if(doneSettle == true) {
            msettleTime  = v_history_timeDT[i]; // 出力：決済日時
            msettlePrice = donePrice;       // 出力：決済価格
            msettlePL    = NormalizeDouble( (-1.0) * (donePrice - mopenPrice) / global_Points, global_Digits);   // 出力：決済損益
            break;
         }
      }  // ショートの場合、ここまで      
   }  //  for(i = ・・・
   
   if(doneSettle == true) {
      return true;
   }
   else {
      // 決済されなかったため、falseを返して終了する。
      return false;
   }
}


//+--------------------------------------------------------------------------+
//| 仮想取引の新規発注をする　　　                                           |
//| ※MODE_ASK、MODE_BIDが必要な部分は、約定日付mOpenTimeで計算した値を使う。|
//+--------------------------------------------------------------------------+
// 20220912 v_OrderSendは、損切値、利確値によらず仮想取引を登録するため、
//          仮想取引発注後に各値を変更するロジックから、v_OrderSend実行前に
//          各値を計算するロジックに変更した。
int v_mOrderSend4(datetime mOpenTime, // 約定時刻
                  string symbol,      // 通貨ペア
                  int cmd,            // OP_BUY, OP_SELL
                  double volume,      // ロット数
                  double price,       // 約定価格
                  int slippage,       // スリップ
                  double stoploss,    // 損切値
                  double takeprofit,  // 利確値
                  string comment,     // コメント＝戦略名
                  int magic,          // マジックナンバー
                  datetime expiration, 
                  color arrow_color) {
   bool mFlag = false;
   int Index = 0;
   int ticket_num =-1;
   double tp = 0.0;
   double sl = 0.0;

   //初期値設定
   double mMarketinfoMODE_ASK = 0.0;
   double mMarketinfoMODE_BID = 0.0;
   double mMarketinfoMODE_POINT = 0.0;
   double mMarketinfoMODE_STOPLEVEL = 0.0;

   if(cmd == OP_BUY || cmd == OP_SELL)  {
      // 20220328追加。約定日が現時点であればMODE_ASK, MODE_BIDを使って仮想取引を登録する。異なれば、その時点の足のClose値を使う。
      // 約定日に使用としている引数mOpenTimeが、
      // ①現在のバー(バー = 0)であれば、MODE_ASKとMODE_BIDの値を取得する。
      // ②現在のバーでなければ、当時のバーのclose値をASK, BIDの値とする。
      int bufShift = iBarShift(global_Symbol, PERIOD_M1, mOpenTime, false);
      if(bufShift == 0) {
         mMarketinfoMODE_ASK = MarketInfo(symbol,MODE_ASK);
         mMarketinfoMODE_BID = MarketInfo(symbol,MODE_BID);
      }
      else {
         mMarketinfoMODE_ASK = iClose(global_Symbol,PERIOD_M1,bufShift);
         mMarketinfoMODE_BID = iClose(global_Symbol,PERIOD_M1,bufShift);
      }
      mMarketinfoMODE_POINT = global_Points;
      mMarketinfoMODE_STOPLEVEL = global_StopLevel;
   }
   else {
      return ERROR;
   }

   // ロングの利益確定最小値＝これより大きな利確値のみ設定可能
   double long_tp_MIN = NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   if(cmd == OP_BUY)  {
      if(takeprofit > long_tp_MIN) {
         tp = NormalizeDouble(takeprofit, global_Digits);
      }
      else {
         tp = 0.0;
      }
   }

   // ロングの損失確定最大値＝これより小さな損切値のみ設定可能
   double long_sl_MAX = NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   if(cmd == OP_BUY)  {
      if(stoploss < long_sl_MAX) {
         sl = NormalizeDouble(stoploss, global_Digits);
      }
      else {
         sl = 0.0;
      }
   }

   // ショートの利益確定最大値＝これより小さな利確値のみ設定可能
   double short_tp_MAX = NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   if(cmd == OP_SELL)  {
      if(takeprofit < short_tp_MAX) {
         tp = NormalizeDouble(takeprofit, global_Digits);
      }
      else {
         tp = 0.0;
      }
   }

   // ショートの損失確定最小値＝これより大きな損切値のみ設定可能
   double short_sl_MIN = NormalizeDouble(mMarketinfoMODE_BID + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits);
   if(cmd == OP_SELL)  {
      if(stoploss > short_sl_MIN) {
         sl = NormalizeDouble(stoploss, global_Digits);
      }
      else {
         sl = 0.0;
      }
   }

   ticket_num = v_OrderSend(mOpenTime, symbol, cmd, volume, price, slippage, sl, tp, comment, magic, expiration, arrow_color);
   if(ticket_num >= 1) {
      return ticket_num;
   }

  return ERROR;
}




//+------------------------------------------------------------------+
//| 仮想取引をすべて消す。　　　　                                   |
//+------------------------------------------------------------------+
void initALL_vOrders_vOrderPLs_vOrderIndexes() {
   int i;
   for(i = 0; i < VTRADENUM_MAX; i++){   // 変数の初期化を目的としているため、全要素を初期化する。
      init_st_vOrders(i);
   }

   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {  // 変数の初期化を目的としているため、全要素を初期化する。
      init_st_vOrderPLs(i);
   }

   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {  // 変数の初期化を目的としているため、全要素を初期化する。
      init_st_vOrderIndexes(i);
   }
}


//
// 平均・偏差の構造体st_vAnalyzedIndexesの値を初期化する。
//
void init_st_vAnalyzedIndexes(st_vAnalyzedIndex &buf_st_vAnalyzedIndexes) {
   buf_st_vAnalyzedIndexes.stageID         = -1;
   buf_st_vAnalyzedIndexes.strategyID      = "";
   buf_st_vAnalyzedIndexes.symbol          = "";
   buf_st_vAnalyzedIndexes.timeframe       = -1;
   buf_st_vAnalyzedIndexes.orderType       = INT_VALUE_MIN;
   buf_st_vAnalyzedIndexes.PLFlag          = INT_VALUE_MIN;
   buf_st_vAnalyzedIndexes.analyzeTime     = -1;
   buf_st_vAnalyzedIndexes.MA_GC_MEAN      = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MA_DC_MEAN      = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MA_Slope5_MEAN  = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MA_Slope25_MEAN = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MA_Slope75_MEAN = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.BB_Width_MEAN   = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.IK_TEN_MEAN     = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.IK_CHI_MEAN     = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.IK_LEG_MEAN     = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MACD_GC_MEAN    = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MACD_DC_MEAN    = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.RSI_VAL_MEAN    = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.STOC_VAL_MEAN   = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.STOC_GC_MEAN    = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.STOC_DC_MEAN    = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.RCI_VAL_MEAN    = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MA_GC_SIGMA     = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MA_DC_SIGMA     = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MA_Slope5_SIGMA = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MA_Slope25_SIGMA= DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MA_Slope75_SIGMA= DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.BB_Width_SIGMA  = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.IK_TEN_SIGMA    = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.IK_CHI_SIGMA    = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.IK_LEG_SIGMA    = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MACD_GC_SIGMA   = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.MACD_DC_SIGMA   = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.RSI_VAL_SIGMA   = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.STOC_VAL_SIGMA  = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.STOC_GC_SIGMA   = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.STOC_DC_SIGMA   = DOUBLE_VALUE_MIN;
   buf_st_vAnalyzedIndexes.RCI_VAL_SIGMA   = DOUBLE_VALUE_MIN;
}

// st_vAnalyzedIndexesBUY_Profit, st_vAnalyzedIndexesBUY_Loss, st_vAnalyzedIndexesSELL_Profit, st_vAnalyzedIndexesSELL_Lossを
// 全て初期化する。
void initALL_vMeanSigma() {
   init_st_vAnalyzedIndexes(st_vAnalyzedIndexesBUY_Profit);
   init_st_vAnalyzedIndexes(st_vAnalyzedIndexesBUY_Loss);
   init_st_vAnalyzedIndexes(st_vAnalyzedIndexesSELL_Profit);
   init_st_vAnalyzedIndexes(st_vAnalyzedIndexesSELL_Loss);
}

//
// 引数iで指定した仮想取引st_vOrders[i]のデータを初期化（＝削除）する。
//
void init_st_vOrders(int i) {
   st_vOrders[i].externalParam = NULL;
   st_vOrders[i].strategyID    = NULL;               // 21:RCISWING, 20:TrendBB, 19:MoveSpeedなど
   st_vOrders[i].symbol        = "";                 // EURUSD-CDなど
   st_vOrders[i].ticket        = INT_VALUE_MIN;      // 通し番号
   st_vOrders[i].timeframe     = INT_VALUE_MIN;      // 時間軸。0は不可。
   st_vOrders[i].orderType     = INT_VALUE_MIN;      // OP_BUYかOPSELL
   st_vOrders[i].openTime      = INT_VALUE_MIN;      // 約定日時。datetime型。
   st_vOrders[i].lots          = DOUBLE_VALUE_MIN;   // ロット数
   st_vOrders[i].openPrice     = DOUBLE_VALUE_MIN;   // 新規建て時の値
   st_vOrders[i].orderTakeProfit = DOUBLE_VALUE_MIN; // 利益確定の値
   st_vOrders[i].orderStopLoss = DOUBLE_VALUE_MIN;   // 損切の値
   st_vOrders[i].closePrice    = DOUBLE_VALUE_MIN;   // 決済値
   st_vOrders[i].closePL       = DOUBLE_VALUE_MIN;   // 決済損益
   st_vOrders[i].closeTime     = INT_VALUE_MIN;      // 決済日時。datetime型。
   st_vOrders[i].estimatePrice = DOUBLE_VALUE_MIN;   // 決済値
   st_vOrders[i].estimatePL    = DOUBLE_VALUE_MIN;   // 決済損益
   st_vOrders[i].estimateTime  = INT_VALUE_MIN;      // 決済日時。datetime型。

}

//
// 引数iで指定した仮想取引の損益集計結果st_vOrderPLs[i]のデータを初期化（＝削除）する。
//
void init_st_vOrderPLs(int i) {
   st_vOrderPLs[i].strategyID  = "";
   st_vOrderPLs[i].symbol      = "";
   st_vOrderPLs[i].timeframe   = INT_VALUE_MIN;
   st_vOrderPLs[i].analyzeTime = INT_VALUE_MIN;
   st_vOrderPLs[i].win         = 0;
   st_vOrderPLs[i].Profit      = 0;
   st_vOrderPLs[i].lose        = 0;
   st_vOrderPLs[i].Loss        = 0;
   st_vOrderPLs[i].even        = 0;
   st_vOrderPLs[i].ProfitFactor = DOUBLE_VALUE_MIN;
   st_vOrderPLs[i].maxDrawdownPIPS = DOUBLE_VALUE_MIN;
   st_vOrderPLs[i].riskRewardRatio = DOUBLE_VALUE_MIN;
   int j;
   for(j = 0; j < HISTORICAL_NUM; j++) {
      st_vOrderPLs[i].latestTrade_time[j] = INT_VALUE_MIN;
      st_vOrderPLs[i].latestTrade_PL[j] = DOUBLE_VALUE_MIN;
   }
   st_vOrderPLs[i].latestTrade_WeightedAVG = DOUBLE_VALUE_MIN;
}


// 構造体配列st_vOrderPLs[]をデフォルト値で埋める。
// forループで時間がかかるため、利用時は注意。
void init_st_vOrderPLs(st_vOrderPL &m_st_vOrderPLs[]) {
   int i;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {    // 構造体配列の初期化を目的としているため、値によらず、全項目を処理対象とする。
      m_st_vOrderPLs[i].strategyID  = "";
      m_st_vOrderPLs[i].symbol      = "";
      m_st_vOrderPLs[i].timeframe   = INT_VALUE_MIN;
      m_st_vOrderPLs[i].analyzeTime = INT_VALUE_MIN;
      m_st_vOrderPLs[i].win         = 0;
      m_st_vOrderPLs[i].Profit      = 0;
      m_st_vOrderPLs[i].lose        = 0;
      m_st_vOrderPLs[i].Loss        = 0;
      m_st_vOrderPLs[i].even        = 0;
   }
}



//
// 引数iで指定した仮想取引の指標st_vOrderIndexes[i]のデータを初期化（＝削除）する。
//
void init_st_vOrderIndexes(int i) {
      st_vOrderIndexes[i].symbol     = "";
      st_vOrderIndexes[i].timeframe  = INT_VALUE_MIN;
      st_vOrderIndexes[i].MA_GC      = INT_VALUE_MAX;
      st_vOrderIndexes[i].MA_DC      = INT_VALUE_MAX;
      st_vOrderIndexes[i].MA_Slope5  = DOUBLE_VALUE_MAX;
      st_vOrderIndexes[i].MA_Slope25 = DOUBLE_VALUE_MAX;
      st_vOrderIndexes[i].MA_Slope75 = DOUBLE_VALUE_MAX;
      st_vOrderIndexes[i].BB_Width   = DOUBLE_VALUE_MAX;
      st_vOrderIndexes[i].IK_TEN     = DOUBLE_VALUE_MAX;
      st_vOrderIndexes[i].IK_CHI     = DOUBLE_VALUE_MAX;
      st_vOrderIndexes[i].IK_LEG     = DOUBLE_VALUE_MAX;
      st_vOrderIndexes[i].MACD_GC    = INT_VALUE_MAX;
      st_vOrderIndexes[i].MACD_DC    = INT_VALUE_MAX;
      st_vOrderIndexes[i].RSI_VAL    = DOUBLE_VALUE_MAX;
      st_vOrderIndexes[i].STOC_VAL   = DOUBLE_VALUE_MAX;
      st_vOrderIndexes[i].STOC_GC    = INT_VALUE_MAX;
      st_vOrderIndexes[i].STOC_DC    = INT_VALUE_MAX;
      st_vOrderIndexes[i].RCI_VAL    = DOUBLE_VALUE_MAX;
}

// 引数で渡したst_vOrderIndexの各項目の値を初期化する。
void init_st_vOrderIndex(st_vOrderIndex &buf_st_vOrderIndex) {
//   buf_st_vOrderIndex.strategyID = "";
   buf_st_vOrderIndex.symbol     = "";
   buf_st_vOrderIndex.timeframe  = INT_VALUE_MIN;
   buf_st_vOrderIndex.calcTime   = INT_VALUE_MIN;
   buf_st_vOrderIndex.MA_GC      = INT_VALUE_MAX;
   buf_st_vOrderIndex.MA_DC      = INT_VALUE_MAX;
   buf_st_vOrderIndex.MA_Slope5  = DOUBLE_VALUE_MAX;
   buf_st_vOrderIndex.MA_Slope25 = DOUBLE_VALUE_MAX;
   buf_st_vOrderIndex.MA_Slope75 = DOUBLE_VALUE_MAX;
   buf_st_vOrderIndex.BB_Width   = DOUBLE_VALUE_MAX;
   buf_st_vOrderIndex.IK_TEN     = DOUBLE_VALUE_MAX;
   buf_st_vOrderIndex.IK_CHI     = DOUBLE_VALUE_MAX;
   buf_st_vOrderIndex.IK_LEG     = DOUBLE_VALUE_MAX;
   buf_st_vOrderIndex.MACD_GC    = INT_VALUE_MAX;
   buf_st_vOrderIndex.MACD_DC    = INT_VALUE_MAX;
   buf_st_vOrderIndex.RSI_VAL    = DOUBLE_VALUE_MAX;
   buf_st_vOrderIndex.STOC_VAL   = DOUBLE_VALUE_MAX;
   buf_st_vOrderIndex.STOC_GC    = INT_VALUE_MAX;
   buf_st_vOrderIndex.STOC_DC    = INT_VALUE_MAX;
   buf_st_vOrderIndex.RCI_VAL    = DOUBLE_VALUE_MAX;
}

// string commentは、21:RCISWING, 20:TrendBB, 19:MoveSpeedなどを設定する。
// 返り値のチケット番号は、1以上
int v_OrderSend(datetime mOpenTime,
                string symbol,
                int cmd,
                double volume,
                double price,
                int slippage,
                double stoploss,
                double takeprofit,
                string comment,
                int magic,
                datetime expiration,
                color arrow_color) {
   int i = 0;
   
   // 引数チェック
   if(StringLen(comment) <= 0) {
      printf("[%d]VT エラー キーワード未設定のため、仮想取引を追加できません", __LINE__);
      return -1;
   }
   // 約定値と損切値、利確値の差が、MarketInfo(global_Symbol, MODE_STOPLEVEL)以下の時は、仮想取引を拒否する。
   double stopLevel = MarketInfo(global_Symbol, MODE_STOPLEVEL);
   if(cmd == OP_BUY) {
      if( (takeprofit - price) / global_Points <= stopLevel) {
         printf("[%d]VT エラー 利確予定値%sと約定予定値%sの差%sが、ストップレベル%s以下のため、ロング発注不可", __LINE__,
                 DoubleToStr(takeprofit, global_Digits),
                 DoubleToStr(price, global_Digits),
                 DoubleToStr((takeprofit - price) / global_Points, global_Digits),
                 DoubleToStr(stopLevel, global_Digits)              
         );
         return -1;
      }
      if( (price - stoploss) / global_Points <= stopLevel) {
         printf("[%d]VT エラー 損切予定値%sと約定予定値%sの差%sが、ストップレベル%s以下のため、ロング発注不可", __LINE__,
                 DoubleToStr(stoploss, global_Digits),
                 DoubleToStr(price, global_Digits),
                 DoubleToStr((price - stoploss) / global_Points, global_Digits),
                 DoubleToStr(stopLevel, global_Digits)                 
         );
         return -1;
      }
   }
   if(cmd == OP_SELL) {
      if( (price - takeprofit) / global_Points <= stopLevel) {
         printf("[%d]VT エラー 利確予定値%sと約定予定値%sの差%sが、ストップレベル%s以下のため、ショート発注不可", __LINE__,
                 DoubleToStr(takeprofit, global_Digits),
                 DoubleToStr(price, global_Digits),
                 DoubleToStr((takeprofit - price) / global_Points, global_Digits),
                 DoubleToStr(stopLevel, global_Digits)                 
         );
         return -1;
      }
      if( (stoploss - price) / global_Points <= stopLevel) {
         printf("[%d]VT エラー 損切予定値%sと約定予定値%sの差%sが、ストップレベル%s以下のため、ショート発注不可", __LINE__,
                 DoubleToStr(stoploss, global_Digits),
                 DoubleToStr(price, global_Digits),
                 DoubleToStr((price - stoploss) / global_Points, global_Digits),
                 DoubleToStr(stopLevel, global_Digits)                 
         );
         return -1;
      }
   }
   
   

   // 通し番号ticketを取得する。設定済み通し番号の最大値+1とする。
   // 同時に利用済み項目数を計算して、配列の空きを計算する。
   int newTick = INT_VALUE_MIN;
   int vorderNum = 0; // 登録済みの仮想取引数。
   
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0.0) {
         break;
      }

      if(newTick < st_vOrders[i].ticket) {
         newTick = st_vOrders[i].ticket;
      }
      vorderNum++;
   }
   // 設定済みの通し番号が無い場合は、1
   if(newTick < 1) {
      newTick = 1;
   }
   // 設定済みの通し番号があった場合は、+1した番号が新しい通し番号
   else {
      newTick++;
   }


   // 配列のうち、使っていないところを探す。
   int newTradeIndex = -1;
   // newTradeIndex = get_NewTradeIndex(st_vOrders);
   newTradeIndex = vorderNum;
   if(newTradeIndex >= VTRADENUM_MAX * 0.95) {
      // 配列がいっぱいになっているため、truncate_st_vOrdersを使って要素を削除し、
      // 配列のうち、使っていないところを再度探す。
      bool flag_truncate_st_vOrders = 
         truncate_st_vOrders(st_vOrders);
      newTradeIndex = get_NewTradeIndex(st_vOrders);
      if(newTradeIndex >= VTRADENUM_MAX) {
         printf("[%d]エラー 仮想取引を追加できません。配列のオーバー", __LINE__);
         return -1;
      }
   }
   else if(newTradeIndex < 0) {
         newTradeIndex = 0;
   }

   // 仮想取引を追加する
   st_vOrders[newTradeIndex].strategyID      = comment;       // 25PIN@@00000や、21:RCISWING, 20:TrendBB, 19:MoveSpeedなど
   st_vOrders[newTradeIndex].symbol          = symbol;        // EURUSD-CDなど
   st_vOrders[newTradeIndex].ticket          = newTick;       // 通し番号
   st_vOrders[newTradeIndex].timeframe       = global_Period; // 時間軸。0は不可。
   st_vOrders[newTradeIndex].orderType       = cmd;           // OP_BUYかOPSELL
   st_vOrders[newTradeIndex].openTime        = mOpenTime;     // 約定日時。datetime型。
   st_vOrders[newTradeIndex].lots            = volume;        // ロット数
   st_vOrders[newTradeIndex].openPrice       = NormalizeDouble(price, global_Digits);       // 新規建て時の値
   st_vOrders[newTradeIndex].orderTakeProfit = NormalizeDouble(takeprofit, global_Digits); // 利益確定の値
   st_vOrders[newTradeIndex].orderStopLoss   = NormalizeDouble(stoploss, global_Digits);   // 損切の値
   st_vOrders[newTradeIndex].closePrice      = 0.0;           // 決済値
   st_vOrders[newTradeIndex].closeTime       = 0;             // 決済日時。datetime型。

   return newTick;
}


// st_vOrder型の配列のうち、使っていないところを探す。
int get_NewTradeIndex(st_vOrder &m_st_vOrders[]) {
   int i;
   int newTradeIndex;
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(m_st_vOrders[i].openTime <= 0) {
         newTradeIndex = i;
         break;
      }
   }

   return i;
}


// st_vOrder型の配列のうち、条件（※）に該当する仮想取引データを削除して、配列内に空きを作る。。
// 条件は、以下のとおり
// ・仮想取引の分析の結果、PFが最低の戦略の取引（最低のPFが1.0以上の場合でも、削除しないと新規仮想取引が登録できないため、最低のPFを削除対象とする）
bool truncate_st_vOrders(st_vOrder &m_st_vOrders[]) {
   //
   // PFが最低の戦略の取引を削除するため、分析を実施する。
   // 
   // 仮想取引の分析
   int vOrderPLsNum = get_st_vOrderPLsNum(st_vOrderPLs);
   // 仮想分析の結果が0件の時は、削除不能
   if(vOrderPLsNum <= 0) {
      printf( "[%d]PB 仮想取引の分析結果が存在しないため、仮想取引の削減は不可能" , __LINE__);
      return false;
   }

   // 分析結果をコピーして、コピー先をPFの昇順でソートする。
   copy_st_vOrderPL(st_vOrderPLs,    // コピー元
                    buf_st_vOrderPLs // コピー先
                    );
   sort_st_vOrderPLs_PF(buf_st_vOrderPLs, g_vSortASK); 

   // PFの昇順ソート済み配列buf_st_vOrderPLsの先頭（0番）から検索して、
   // 取引が発生している前提で、0以上で最小のPFを取得する。0未満のプロフィットファクタは異常値と判断する。
   double minPF = DOUBLE_VALUE_MIN;
   int    tradeNum = INT_VALUE_MIN;
   int i;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(buf_st_vOrderPLs[i].analyzeTime <= 0) {
         break;
      }
      // 前提として、全勝しているときのPFはDOUBLE_VALUE_MAX、全敗しているときは０。取引が０件など異常値DOUBLE_VALUE_MIN以外は０以上。
      // 事前にPFの昇順ソート済みのため、最初に取引があり、かつ、PF計算済みの分析結果を以降の処理対象とする。
      minPF    = NormalizeDouble(buf_st_vOrderPLs[i].ProfitFactor, global_Digits);
      tradeNum = buf_st_vOrderPLs[i].win + buf_st_vOrderPLs[i].lose + buf_st_vOrderPLs[i].even;
      
      if(minPF > 0.0 && tradeNum > 0) {
         break;
      }
   }

   if(minPF < 0.0 || tradeNum <= 0) {
      printf( "[%d]PB 仮想取引の分析結果の最小PF>%s<が負で異常値。仮想取引削除は不可能" , __LINE__, DoubleToStr(minPF, global_Digits));
      return false;
   }

   // 最小のPFを持つ分析結果を取得する
   int selectedNum = 
      select_st_vOrderPLs_byPF(buf_st_vOrderPLs,     // 抽出元
                               minPF,                // 抽出条件に使うプロフィットファクタ 
                               g_Lower_Eq,           // g_Lower_Eq=-1＝PF以下を抽出
                               selected_st_vOrderPLs // 出力：抽出結果
                               );
   if(selectedNum <= 0) {
      printf( "[%d]PB 仮想取引の分析結果のうち、最小PF>%s<を持つデータが無いため、仮想取引削除は不可能" , __LINE__,
               DoubleToStr(minPF, global_Digits));
      return false;
   }

   // 最小のPFを持つ分析結果selected_st_vOrderPLsの戦略名をキーとして、
   // 仮想取引を削除する。
   int count = 0;
   int bufCount = 0;
   for(i = 0; i < selectedNum; i++) {
      if(st_vOrders[i].openTime == 0) {
         break;
      }
      else {
         bufCount = delete_vOrder_StrategyID(st_vOrders[i].strategyID);
         count = count + bufCount;
         printf( "[%d]PB >%s<の仮想取引>%d<件を削除した　　総削除件数=>%d<" , __LINE__, 
                  st_vOrders[i].strategyID,
                  bufCount,
                  count);
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| 仮想取引を1件削除する。削除後、空いたところを詰める              |
//+------------------------------------------------------------------+
// st_vOrders[i].ticket = 引数(tickNum)の仮想取引を削除する。
int delete_vOrder(int tickNum) {
   int i;
   int j;
   int count = 0;
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }

      if(st_vOrders[i].ticket == tickNum) {
         //
         // 削除する仮想取引に紐づく指標計算結果の削除
         //
         bool flagSameVTrade = false;
         for(j = 0; j < VTRADENUM_MAX; j++) {   // 同じキーを持つ仮想取引を探す。
            if(st_vOrders[j].openTime <= 0) {
               break;
            }

            if(j != i 
               && StringLen(st_vOrders[j].strategyID)
               && StringLen(st_vOrders[i].strategyID)
               && StringLen(st_vOrders[j].symbol)
               && StringLen(st_vOrders[i].symbol)
               && StringCompare(st_vOrders[j].strategyID, st_vOrders[i].strategyID) ==0
               && StringCompare(st_vOrders[j].symbol, st_vOrders[i].symbol) ==0
               && st_vOrders[j].timeframe == st_vOrders[i].timeframe
               && st_vOrders[j].openTime == st_vOrders[i].openTime) {
               flagSameVTrade = true;
               break;
            }
         }
         // 同じキーを持つ仮想取引が無ければ、指標計算結果も削除する。
         if(flagSameVTrade == false) {
            delete_st_vOrderIndexes(st_vOrders[i].strategyID, st_vOrders[i].symbol, st_vOrders[i].timeframe, st_vOrders[i].openTime);
         }
         
         // 仮想取引の削除
         init_st_vOrders(i);
         count++;
      }
   }
   
   // st_vOrders[]の残りが1件以上の時は、削除した配列項目を詰める
   delete_empty_vOrder(st_vOrders) ;

   return count;
}

void delete_empty_vOrder(st_vOrder &m_st_vOrders[]) {
   int i;
   int j;
   // st_vOrders[]の残りが1件以上の時は、削除した配列項目を詰める
   int tmpOrederNum = get_vOrdersNum_SeekALL();
   
   int vOrderNum = 0;
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(m_st_vOrders[i].openTime <= 0) {
         break;
      }

      if(m_st_vOrders[i].ticket > 0) {
         vOrderNum++;
      }
   }
   if(vOrderNum >= 1) {
      // 配列の末尾1つ手前から先頭にさかのぼっていき、空欄があれば、詰める
      for(i = VTRADENUM_MAX - 2; i >= 0; i--) {  // どこに空きがあるか判断できないため、全件を対象とする。
         if(m_st_vOrders[i].ticket > 0) {
            // 何もしない
         }
         else {  // 後ろからさかのぼっていく過程で、空欄を見つけたので、前に詰める。
            for(j = i + 1; j < VTRADENUM_MAX; j++) {
               if(m_st_vOrders[j].openTime <= 0) {
                  break;
               }
               copy_st_vOrder(m_st_vOrders[j], // コピー元
                              m_st_vOrders[i]  // コピー先
                                );
               // copy_st_vOrder関数だけでは、m_st_vOrders[]内に同じデータが重複するため、
               // コピー元は初期化する。
               init_st_vOrders(j);
            }
         }
      }
   }
}


void delete_empty_vOrderPL(st_vOrderPL &m_st_vOrderPLs[]) {
   int i;
   int j;
   // st_vOrders[]の残りが1件以上の時は、削除した配列項目を詰める
   int vOrderPLNum = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(m_st_vOrderPLs[i].analyzeTime <= 0) {
         break;
      }

      if(m_st_vOrderPLs[i].analyzeTime > 0) {
         vOrderPLNum++;
      }
   }
   if(vOrderPLNum >= 1) {
      // 配列の末尾1つ手前から先頭にさかのぼっていき、空欄があれば、詰める
      for(i = VOPTPARAMSNUM_MAX - 2; i >= 0; i--) {  // どこに空きがあるか判断できないため、全件を対象とする。
         if(m_st_vOrderPLs[i].analyzeTime > 0) {
            // 何もしない
         }
         else {  // 後ろからさかのぼっていく過程で、空欄を見つけたので、前に詰める。
            for(j = i + 1; j < VOPTPARAMSNUM_MAX; j++) {
               if(m_st_vOrderPLs[j].analyzeTime <= 0) {
                  break;
               }
               copy_st_vOrderPL(m_st_vOrderPLs[j], // コピー元
                                m_st_vOrderPLs[i]  // コピー先
                                );
               // copy_st_vOrder関数だけでは、m_st_vOrders[]内に同じデータが重複するため、
               // コピー元は初期化する。
               init_st_vOrderPLs(j);
            }
         }
      }
   }
}

// st_vOrders[i].openTime = 引数(約定時間)の仮想取引を削除する。
int delete_vOrder(datetime mTime)  {
   int count = 0;
   for(int i = 0; i < VTRADENUM_MAX; i++)   {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }

      if(st_vOrders[i].openTime == mTime)   {
         //
         // 削除する仮想取引に紐づく指標計算結果の削除
         //
         bool flagSameVTrade = false;
         for(int j = 0; j < VTRADENUM_MAX; j++) {   // 同じキーを持つ仮想取引を探す。
            if(st_vOrders[j].openTime <= 0) {
               break;
            }

            if(j != i 
               && StringLen(st_vOrders[j].strategyID)
               && StringLen(st_vOrders[i].strategyID)
               && StringLen(st_vOrders[j].symbol)
               && StringLen(st_vOrders[i].symbol)
               && StringCompare(st_vOrders[j].strategyID, st_vOrders[i].strategyID) ==0
               && StringCompare(st_vOrders[j].symbol, st_vOrders[i].symbol) ==0
               && st_vOrders[j].timeframe == st_vOrders[i].timeframe
               && st_vOrders[j].openTime == st_vOrders[i].openTime) {
               flagSameVTrade = true;
               break;
            }
         }
         // 同じキーを持つ仮想取引が無くなれば、指標計算結果のメンバも削除する。
         if(flagSameVTrade == false) {
            delete_st_vOrderIndexes(st_vOrders[i].strategyID, st_vOrders[i].symbol, st_vOrders[i].timeframe, st_vOrders[i].openTime);
         }
         // 同じキーを持つ仮想取引が存在すれば、指標計算結果のメンバを残す。
         else {
            // 何もしない
         }
               
         // 仮想取引の削除
         init_st_vOrders(i);
         count++;
      }
   }

   // st_vOrders[]の残りが1件以上の時は、削除した配列項目を詰める
   delete_empty_vOrder(st_vOrders) ;

   return count;
}


// 約定日が、引数(Arg1)以前の仮想取引を削除する
int delete_vOrder_BeforeArg1(datetime mTime)  {
   int count = 0;
   for(int i = 0; i < VTRADENUM_MAX; i++)   {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }   
      if(st_vOrders[i].openTime <= mTime)   {
         //
         // 削除する仮想取引に紐づく指標計算結果の削除
         //
         bool flagSameVTrade = false;
         for(int j = 0; j < VTRADENUM_MAX; j++) {   // 同じキーを持つ仮想取引を探す。
            if(st_vOrders[j].openTime <= 0) {
               break;
            }

            if(j != i 
               && StringLen(st_vOrders[j].strategyID)
               && StringLen(st_vOrders[i].strategyID)
               && StringLen(st_vOrders[j].symbol)
               && StringLen(st_vOrders[i].symbol)
               && StringCompare(st_vOrders[j].strategyID, st_vOrders[i].strategyID) ==0
               && StringCompare(st_vOrders[j].symbol, st_vOrders[i].symbol) ==0
               && st_vOrders[j].timeframe == st_vOrders[i].timeframe
               && st_vOrders[j].openTime == st_vOrders[i].openTime) {
               flagSameVTrade = true;
               break;
            }
         }
         // 同じキーを持つ仮想取引が無くなれば、指標計算結果のメンバも削除する。
         if(flagSameVTrade == false) {
            delete_st_vOrderIndexes(st_vOrders[i].strategyID, st_vOrders[i].symbol, st_vOrders[i].timeframe, st_vOrders[i].openTime);
         }
         // 同じキーを持つ仮想取引が存在すれば、指標計算結果のメンバを残す。
         else {
            // 何もしない
         }
               
         // 仮想取引の削除
         init_st_vOrders(i);
         count++;
      }
   }

   // st_vOrders[]の残りが1件以上の時は、削除した配列項目を詰める
   delete_empty_vOrder(st_vOrders) ;

   return count;
}


// 戦略名が、引数(Arg1)の仮想取引を削除する
int delete_vOrder_StrategyID(string mStrategy)  {
   int count = 0;
   for(int i = 0; i < VTRADENUM_MAX; i++)   {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }
      if(StringLen(st_vOrders[i].strategyID) > 0 && StringLen(mStrategy) > 0 && StringCompare(st_vOrders[i].strategyID, mStrategy) ==0)   {
         // 仮想取引の削除
         init_st_vOrders(i);
         count++;
      }
   }
   // st_vOrders[]の残りが1件以上の時は、削除した配列項目を詰める
   delete_empty_vOrder(st_vOrders) ;

   return count;
}

int delete_vOrderPL(string mStrategy)  {
   int count = 0;
   for(int i = 0; i < VOPTPARAMSNUM_MAX; i++)   {
      if(st_vOrderPLs[i].analyzeTime <= 0) {
         break;
      }
      if(StringLen(st_vOrderPLs[i].strategyID) > 0 && StringLen(mStrategy) > 0 && StringCompare(st_vOrderPLs[i].strategyID, mStrategy) ==0)   {
         // 仮想取引の削除
         init_st_vOrderPLs(i);
         count++;
      }
   }
   
   // st_vOrders[]の残りが1件以上の時は、削除した配列項目を詰める
   delete_empty_vOrderPL(st_vOrderPLs) ;
   
   return count;
}



bool delete_st_vOrderIndexes(string m_strategyID, string m_symbol, int m_timeframe, datetime m_openTime) {
   bool delFlag = false;
   for(int i = 0; i< VTRADENUM_MAX; i++) {
      if(st_vOrderIndexes[i].calcTime <= 0) {
         break;
      }

      if(StringLen(st_vOrderIndexes[i].symbol) > 0 && StringLen(m_symbol) > 0 && StringCompare(st_vOrderIndexes[i].symbol, m_symbol) ==0
         && st_vOrderIndexes[i].timeframe == m_timeframe
         && st_vOrderIndexes[i].calcTime  == m_openTime) {
         delFlag = true;
         init_st_vOrderIndexes(i);
      }
   }

   // st_vOrderIndexes[]の残りが1件以上の時は、削除した配列項目を詰める
   delete_empty_vOrderIndex(st_vOrderIndexes) ;
 
   return delFlag;
}



void delete_empty_vOrderIndex(st_vOrderIndex &m_st_vOrderIndexes[]) {
   int i;
   int j;
   // st_vOrderIndexes[]の残りが1件以上の時は、削除した配列項目を詰める
   int vOrderIndexNum = 0;
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(m_st_vOrderIndexes[i].calcTime > 0) {
         vOrderIndexNum++;
      }
   }
   if(vOrderIndexNum >= 1) {
      // 配列の末尾1つ手前から先頭にさかのぼっていき、空欄があれば、詰める
      for(i = VTRADENUM_MAX - 2; i >= 0; i--) {
         if(m_st_vOrderIndexes[i].calcTime > 0) {
            // 何もしない
         }
         else {  // 後ろからさかのぼっていく過程で、空欄を見つけたので、前に詰める。
            for(j = i + 1; j < VTRADENUM_MAX; j++) {
               if(m_st_vOrderIndexes[j].calcTime <= 0) {
                  break;
               }
               copy_st_vOrderIndex(m_st_vOrderIndexes[j], // コピー元   
                                   m_st_vOrderIndexes[i]    // コピー先
                                   );
               // copy_st_vOrderIndexes関数だけでは、m_st_vOrderIndexes[]内に同じデータが重複するため、
               // コピー元は初期化する。
               init_st_vOrderIndexes(j);

            }
         }
      }
   }
}


// 引数の値を持つ仮想取引の個数を返す。
// 計算に失敗した場合は、-1を返す。
int getNumber_of_vOrders(string strategyID,             // 入力：検索キー。戦略名
                         string symbol,                 // 入力：検索キー。EURUSD-CDなど
                         int    timeframe,              // 入力：検索キー。時間軸。0は不可。PERIOD_M1～PERIOD_MN1
                         datetime FROM_vOrder_openTime, // 入力：検索キー。評価対象となる仮想取引の約定時間がこの値以降。
                         datetime TO_vOrder_openTime    // 入力：検索キー。評価対象となる仮想取引の約定時間がこの値以前。
                        )  {
   int count = 0;
   int i;
   if(StringLen(strategyID) <= 0)   {
      return -1;
   }
   if(StringLen(symbol) <= 0) {
      return -1;
   }
   if(timeframe < 0)  {
      return -1;
   }

   // 対象とする最初の時間が負の場合は、仮想取引の先頭から計算対象とする。
   if(FROM_vOrder_openTime < 0) {
      FROM_vOrder_openTime = 0;
   }

   // 対象とする最後の時間が負の場合は、仮想取引の約定時間最大値を計算する
   if(TO_vOrder_openTime < 0)  {
      datetime maxOpenTime = 0;
      for(int ii = 0; ii < VTRADENUM_MAX; ii++) {
         if(st_vOrders[i].openTime <= 0) {
            break;
         }
         if(maxOpenTime < st_vOrders[i].openTime) {
            maxOpenTime = st_vOrders[i].openTime;
         }
      }

      TO_vOrder_openTime = maxOpenTime;
   }

   if(TO_vOrder_openTime < FROM_vOrder_openTime){
      return -1;
   }

   // 検索キーに該当する仮想取引数をカウントするループ
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }

      if(StringLen(st_vOrders[i].strategyID) > 0 && StringLen(strategyID) > 0 && StringCompare(st_vOrders[i].strategyID, strategyID, true) == 0
         && StringLen(st_vOrders[i].symbol) > 0 && StringLen(symbol) > 0 && StringCompare(st_vOrders[i].symbol, symbol, true) == 0
         && st_vOrders[i].timeframe == timeframe
         && st_vOrders[i].openTime >= FROM_vOrder_openTime
         && st_vOrders[i].openTime <= TO_vOrder_openTime)  {
         count++;
      }
   }
   return count;
}




//+------------------------------------------------------------------+
//| 仮想取引をファイル出力する（ファイル名固定）         　　　　　  |
//+------------------------------------------------------------------+
void write_vOrders()  {
   if(VT_FILEIO_FLAG == false) {
      return ;
   }
   int i = 0;
   string mFileName = "virtualTrade.csv";
   int fileHandle1 = FileOpen(mFileName, FILE_WRITE | FILE_CSV,",");

   int outputNum = 0; // 出力した仮想取引数。
   if(fileHandle1 != INVALID_HANDLE) {
      // 仮想取引が発生していなければ、その旨をファイル出力して、処理終了。
      int bufCount = 0; // 発生した仮想取引の件数。
      for(i = 0; i < VTRADENUM_MAX; i++)   {
         if(st_vOrders[i].openTime <= 0)  {
         }

         if(st_vOrders[i].openTime > 0)  {
            bufCount++;
         }
      }
      if(bufCount == 0){
         FileWrite(fileHandle1, "仮想取引は、未発生。");
         FileClose(fileHandle1);
         return ;
      }
      // 仮想取引が発生していない場合、ここまで。

      FileWrite(fileHandle1,
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
            if(st_vOrders[i].orderType == OP_BUY)   {
               bufBuySell = "買い";
            }
            else if(st_vOrders[i].orderType == OP_SELL) {
               bufBuySell = "売り";
            }
            else {
               bufBuySell = IntegerToString(st_vOrders[i].orderType);
            }
            FileWrite(fileHandle1,
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

      FileWrite(fileHandle1,
                "No",
                "戦略名",
                "通貨ペア",
                "時間軸",
                "勝ち数",
                "負け数",
                "引き分け",
                "利益",
                "損失",
                "分析日時",
                "PF",
                "最大ドローダウン",
                "リスクリワード率"
               );

      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(st_vOrderPLs[i].analyzeTime <= 0) {
            break;
         }

         if(st_vOrderPLs[i].analyzeTime > 0) {
            string bufPF = "";
            if(st_vOrderPLs[i].Loss == 0.0 && st_vOrderPLs[i].Profit > 0.0) {
               bufPF = "全勝中";
            }
            else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit > 0.0) {
               bufPF = DoubleToStr(MathAbs(NormalizeDouble(st_vOrderPLs[i].Profit, global_Digits) / NormalizeDouble(st_vOrderPLs[i].Loss, global_Digits)));
            }
            else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit == 0.0) {
               bufPF = "全て敗け";
            }
            else {
               bufPF = "**";
            }

            FileWrite(fileHandle1,
                      i,
                      st_vOrderPLs[i].strategyID,
                      st_vOrderPLs[i].symbol,
                      st_vOrderPLs[i].timeframe,
                      st_vOrderPLs[i].win,
                      st_vOrderPLs[i].lose,
                      st_vOrderPLs[i].even,
                      st_vOrderPLs[i].Profit,
                      st_vOrderPLs[i].Loss,
                      TimeToStr(st_vOrderPLs[i].analyzeTime),
                      bufPF,
                      st_vOrderPLs[i].maxDrawdownPIPS,
                      st_vOrderPLs[i].riskRewardRatio
                     );
         }
      }
   } // if(fileHandle1 != INVALID_HANDLE){
   else {
      printf("[%d]VT ファイルオープンエラー：仮想取引%s", __LINE__, mFileName);
      Print(GetLastError());
   }

   FileClose(fileHandle1);
}

//+------------------------------------------------------------------+
//| 仮想取引をファイル出力する（引数でファイル名指定）   　　　　　  |
//+------------------------------------------------------------------+
void write_vOrders(string mFileName)  {
   if(VT_FILEIO_FLAG == false) {
      return ;
   }
   int i = 0;
   int fileHandle1 = FileOpen(mFileName, FILE_WRITE | FILE_CSV,",");

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

      FileWrite(fileHandle1,
                "No",
                "戦略名",
                "通貨ペア",
                "時間軸",
                "勝ち数",
                "負け数",
                "引き分け",
                "利益",
                "損失",
                "分析日時",
                "PF",
                "PF項目版",
                "最大ドローダウン",
                "リスクリワード率"
               );

      for(i = 0; i < VOPTPARAMSNUM_MAX; i++){
         if(st_vOrderPLs[i].analyzeTime <= 0)  {
            break;
         }
         if(st_vOrderPLs[i].analyzeTime > 0)  {
            string bufPF = "";
            if(st_vOrderPLs[i].Loss == 0.0 && st_vOrderPLs[i].Profit > 0.0)  {
               bufPF = "全勝中";
            }
            else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit > 0.0) {
                  bufPF = DoubleToStr(MathAbs(NormalizeDouble(st_vOrderPLs[i].Profit, global_Digits) / NormalizeDouble(st_vOrderPLs[i].Loss, global_Digits)));
            }
            else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit == 0.0) {
                     bufPF = "全て敗け";
            }
            else {
               bufPF = "**";
            }

            FileWrite(fileHandle1,
                      i,
                      st_vOrderPLs[i].strategyID,
                      st_vOrderPLs[i].symbol,
                      st_vOrderPLs[i].timeframe,
                      st_vOrderPLs[i].win,
                      st_vOrderPLs[i].lose,
                      st_vOrderPLs[i].even,
                      st_vOrderPLs[i].Profit,
                      st_vOrderPLs[i].Loss,
                      TimeToStr(st_vOrderPLs[i].analyzeTime),
                      bufPF,
                      st_vOrderPLs[i].ProfitFactor,
                      st_vOrderPLs[i].maxDrawdownPIPS,
                      st_vOrderPLs[i].riskRewardRatio
                     );
         }
      }
   } // if(fileHandle1 != INVALID_HANDLE){
   else {
      printf("[%d]VT ファイルオープンエラー：仮想取引%s", __LINE__, mFileName);
      Print(GetLastError());
   }

   FileClose(fileHandle1);
}


//+------------------------------------------------------------------+
//| 仮想取引を画面とログ出力する         　　　　　  |
//+------------------------------------------------------------------+
void output_vOrderPLs(st_vOrderPL &m_st_vOrderPLs[])  {
   int i = 0;
   string outputBuf = "";

   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(m_st_vOrderPLs[i].analyzeTime <= 0) {
         break;
      }
      if(m_st_vOrderPLs[i].analyzeTime > 0) {
         string bufPF = "";
         if(m_st_vOrderPLs[i].Loss == 0.0 && m_st_vOrderPLs[i].Profit > 0.0) {
            bufPF = "全勝中";
         }
         else if(m_st_vOrderPLs[i].Loss < 0.0 && m_st_vOrderPLs[i].Profit > 0.0) {
            bufPF = DoubleToStr(MathAbs(NormalizeDouble(m_st_vOrderPLs[i].Profit, global_Digits) / NormalizeDouble(m_st_vOrderPLs[i].Loss, global_Digits)));
         }
         else if(m_st_vOrderPLs[i].Loss < 0.0 && m_st_vOrderPLs[i].Profit == 0.0) {
            bufPF = "全て敗け";
         }
         else {
            bufPF = "**";
         }

         outputBuf = "No=" + ZeroPadding(i, 4); //IntegerToString(i);
         outputBuf = outputBuf + "戦略名="  + m_st_vOrderPLs[i].strategyID + ", ";
         outputBuf = outputBuf + "総数数="  + IntegerToString(m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even) + ", ";
         outputBuf = outputBuf + "勝ち数="  + IntegerToString(m_st_vOrderPLs[i].win) + ", ";
         outputBuf = outputBuf + "負け数"   + IntegerToString(m_st_vOrderPLs[i].lose) + ", ";
         outputBuf = outputBuf + "引き分け="+ IntegerToString(m_st_vOrderPLs[i].even) + ", ";
         outputBuf = outputBuf + "利益="    + DoubleToStr(m_st_vOrderPLs[i].Profit, global_Digits) + ", ";
         outputBuf = outputBuf + "損失="    + DoubleToStr(m_st_vOrderPLs[i].Loss, global_Digits) + ", ";
         outputBuf = outputBuf + "分析日時="+TimeToStr(m_st_vOrderPLs[i].analyzeTime) + ", ";
         outputBuf = outputBuf + "PF="  + DoubleToStr(m_st_vOrderPLs[i].ProfitFactor, global_Digits) + ", ";
         outputBuf = outputBuf + "最大ドローダウン="+ DoubleToStr(m_st_vOrderPLs[i].maxDrawdownPIPS, global_Digits) + ", ";
         outputBuf = outputBuf + "リスクリワード率="+ DoubleToStr(m_st_vOrderPLs[i].riskRewardRatio, global_Digits);
      int ii;
      if(m_st_vOrderPLs[i].latestTrade_time[0] <= 0) {
         outputBuf = outputBuf + "損益加重平均の計算対象無し";
      }
      else {
         outputBuf = outputBuf + "損益加重平均=" + DoubleToStr(m_st_vOrderPLs[i].latestTrade_WeightedAVG, global_Digits);
      }
      for(ii = 0; ii < HISTORICAL_NUM; ii++) {
         if(m_st_vOrderPLs[i].latestTrade_time[ii] <= 0) {
            break;
         }
         outputBuf = outputBuf + "[" + IntegerToString(ii) + "]" 
                     + ",時間=" + TimeToString(m_st_vOrderPLs[i].latestTrade_time[ii] )
                     + ",損益=" + DoubleToStr(m_st_vOrderPLs[i].latestTrade_PL[ii], global_Digits); 
      }
      if(m_st_vOrderPLs[i].latestTrade_time[0] <= 0) {
         // 追加文字列は無い
      }
      else {
         outputBuf = outputBuf + ",加重平均=" + DoubleToStr(m_st_vOrderPLs[i].latestTrade_WeightedAVG, global_Digits); 
      }
         
         printf("[%d]VT %s", __LINE__, outputBuf);
         
       }
   } 
}



void write_vOrderPLs(st_vOrderPL &m_st_vOrderPLs[]) {
   string outputBuf = "";
   if(VT_FILEIO_FLAG == false) {
      return ;
   }
   int i = 0;
   int fileHandle1 = FileOpen("st_vOrderPL.csv", FILE_WRITE | FILE_CSV,",");   
   if(fileHandle1 != INVALID_HANDLE) {
      FileWrite(fileHandle1,
                "No",
                "戦略名",
                "通貨ペア",
                "時間軸",
                "勝ち数",
                "負け数",
                "引き分け",
                "利益",
                "損失",
                "分析日時",
                "PF",
                "PF項目版",
                "最大ドローダウン",
                "リスクリワード率",
                "損益加重平均"
               );
               string bufWp="";
      for(i = 0; i < VOPTPARAMSNUM_MAX; i++){
         if(st_vOrderPLs[i].analyzeTime <= 0)  {
            break;
         }
         if(st_vOrderPLs[i].analyzeTime > 0)  {
            string bufPF = "";
            if(st_vOrderPLs[i].Loss == 0.0 && st_vOrderPLs[i].Profit > 0.0)  {
               bufPF = "全勝中";
            }
            else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit > 0.0) {
                  bufPF = DoubleToStr(MathAbs(NormalizeDouble(st_vOrderPLs[i].Profit, global_Digits) / NormalizeDouble(st_vOrderPLs[i].Loss, global_Digits)));
            }
            else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit == 0.0) {
                     bufPF = "全て敗け";
            }
            else {
               bufPF = "**";
            }

            // 加重平均の計算根拠
            bufWp = "";
            for(int ii = 0; ii < HISTORICAL_NUM; ii++) {
               if(st_vOrderPLs[i].latestTrade_time[ii] <= 0) {
                  break;
               }

               bufWp = bufWp + "," + IntegerToString(ii) 
                     + ",時間=" + TimeToString(st_vOrderPLs[i].latestTrade_time[ii] )
                     + ",損益=" + DoubleToStr(st_vOrderPLs[i].latestTrade_PL[ii], global_Digits); 
            }
            FileWrite(fileHandle1,
                      i,
                      st_vOrderPLs[i].strategyID,
                      st_vOrderPLs[i].symbol,
                      st_vOrderPLs[i].timeframe,
                      st_vOrderPLs[i].win,
                      st_vOrderPLs[i].lose,
                      st_vOrderPLs[i].even,
                      st_vOrderPLs[i].Profit,
                      st_vOrderPLs[i].Loss,
                      TimeToStr(st_vOrderPLs[i].analyzeTime),
                      bufPF,
                      st_vOrderPLs[i].ProfitFactor,
                      st_vOrderPLs[i].maxDrawdownPIPS,
                      st_vOrderPLs[i].riskRewardRatio,
                      st_vOrderPLs[i].latestTrade_WeightedAVG,
                      bufWp
                     );
         }
      }
   }
   FileClose(fileHandle1);
} 




void output_vOrderPLs(st_vOrderPL &m_st_vOrderPLs)  {
   string outputBuf = "";

   if(m_st_vOrderPLs.analyzeTime > 0) {
      string bufPF = "";
      if(m_st_vOrderPLs.Loss == 0.0 && m_st_vOrderPLs.Profit > 0.0) {
         bufPF = "全勝中";
      }
      else if(m_st_vOrderPLs.Loss < 0.0 && m_st_vOrderPLs.Profit > 0.0) {
         bufPF = DoubleToStr(MathAbs(NormalizeDouble(m_st_vOrderPLs.Profit, global_Digits) / NormalizeDouble(m_st_vOrderPLs.Loss, global_Digits)));
      }
      else if(m_st_vOrderPLs.Loss < 0.0 && m_st_vOrderPLs.Profit == 0.0) {
         bufPF = "全て敗け";
      }
      else {
         bufPF = "**";
      }

      outputBuf = outputBuf + "戦略名="  + m_st_vOrderPLs.strategyID + ", ";
      outputBuf = outputBuf + "勝ち数="  + IntegerToString(m_st_vOrderPLs.win) + ", ";
      outputBuf = outputBuf + "負け数"   + IntegerToString(m_st_vOrderPLs.lose) + ", ";
      outputBuf = outputBuf + "引き分け="+ IntegerToString(m_st_vOrderPLs.even) + ", ";
      outputBuf = outputBuf + "利益="    + DoubleToStr(m_st_vOrderPLs.Profit, global_Digits) + ", ";
      outputBuf = outputBuf + "損失="    + DoubleToStr(m_st_vOrderPLs.Loss, global_Digits) + ", ";
      outputBuf = outputBuf + "分析日時="+TimeToStr(m_st_vOrderPLs.analyzeTime) + ", ";
      outputBuf = outputBuf + "PF="  + DoubleToStr(m_st_vOrderPLs.ProfitFactor, global_Digits) + ", ";
      outputBuf = outputBuf + "最大ドローダウン="+ DoubleToStr(m_st_vOrderPLs.maxDrawdownPIPS, global_Digits) + ", ";
      outputBuf = outputBuf + "リスクリワード率="+ DoubleToStr(m_st_vOrderPLs.riskRewardRatio, global_Digits) + ", ";
      int i;
      if(m_st_vOrderPLs.latestTrade_time[0] <= 0) {
         outputBuf = outputBuf + "損益加重平均の計算対象無し";
      }
      else {
         outputBuf = outputBuf + "損益加重平均=";
      }
      for(i = 0; i < HISTORICAL_NUM; i++) {
         if(m_st_vOrderPLs.latestTrade_time[i] <= 0) {
            break;
      }
         outputBuf = outputBuf + IntegerToString(i) 
                     + ":時間=" + TimeToString(m_st_vOrderPLs.latestTrade_time[i] )
                     + ":損益=" + DoubleToStr(m_st_vOrderPLs.latestTrade_PL[i], global_Digits); 
      }
      if(m_st_vOrderPLs.latestTrade_time[0] <= 0) {
         // 追加文字列は無い
      }
      else {
         outputBuf = outputBuf + "加重平均=" + DoubleToStr(m_st_vOrderPLs.latestTrade_WeightedAVG, global_Digits); 
      }



      printf("[%d]VT %s", __LINE__, outputBuf);

   } 
}
//+------------------------------------------------------------------+
//| 仮想取引に紐づく指標をファイル出力する（引数でファイル名指定）   　　　　　  |
//+------------------------------------------------------------------+
void write_vIndexes(string mFileName)  {
   if(VT_FILEIO_FLAG == false) {
      return ;
   }
   int i = 0;
   int fileHandle1 = FileOpen(mFileName, FILE_WRITE | FILE_CSV,",");

   int outputNum = 0; // 出力した仮想取引数。
   if(fileHandle1 != INVALID_HANDLE) {
      // 指標データが発生していなければ、その旨をファイル出力して、処理終了。
      int bufCount = 0; // 発生した仮想取引の件数。
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(st_vOrderIndexes[i].calcTime <= 0) {
            break;
         }
         if(st_vOrderIndexes[i].calcTime > 0) {
            bufCount++;
         }
      }
      if(bufCount == 0)
        {
         FileWrite(fileHandle1,
                   "指標データは、未発生。");
         FileClose(fileHandle1);
         return ;
        }
      // 仮想取引が発生していない場合、ここまで。

      FileWrite(fileHandle1,
                "No",
                "戦略名",
                "通貨ペア",
                "時間軸",
                "基準日",
                "MA_GC",
                "MA_DC",
                "MA_Slope5",
                "MA_Slope25",
                "MA_Slope75",
                "BB_Width",
                "IK_TEN",
                "IK_CHI",
                "IK_LEG",
                "MACD_GC",
                "MACD_DC",
                "RSI_VAL",
                "STOC_VAL",
                "STOC_GC",
                "STOC_DC",
                "RCI_VAL"
               );
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(st_vOrderIndexes[i].calcTime <= 0) {
            break;
         }
         if(st_vOrderIndexes[i].calcTime > 0) {
            string bufBuySell = "";

            FileWrite(fileHandle1,
                      i,
                      st_vOrderIndexes[i].symbol,
                      IntegerToString(st_vOrderIndexes[i].timeframe),
                      TimeToStr(st_vOrderIndexes[i].calcTime),
                      IntegerToString(st_vOrderIndexes[i].MA_GC),
                      IntegerToString(st_vOrderIndexes[i].MA_DC),
                      DoubleToStr(st_vOrderIndexes[i].MA_Slope5),
                      DoubleToStr(st_vOrderIndexes[i].MA_Slope25),
                      DoubleToStr(st_vOrderIndexes[i].MA_Slope75),
                      DoubleToStr(st_vOrderIndexes[i].BB_Width, global_Digits),
                      DoubleToStr(st_vOrderIndexes[i].IK_TEN, global_Digits),
                      DoubleToStr(st_vOrderIndexes[i].IK_CHI, global_Digits),
                      DoubleToStr(st_vOrderIndexes[i].IK_LEG, global_Digits),
                      IntegerToString(st_vOrderIndexes[i].MACD_GC),
                      IntegerToString(st_vOrderIndexes[i].MACD_DC),
                      DoubleToStr(st_vOrderIndexes[i].RSI_VAL, global_Digits),
                      DoubleToStr(st_vOrderIndexes[i].STOC_VAL, global_Digits),
                      DoubleToStr(st_vOrderIndexes[i].STOC_GC, global_Digits),
                      DoubleToStr(st_vOrderIndexes[i].STOC_DC, global_Digits),
                      DoubleToStr(st_vOrderIndexes[i].RCI_VAL, global_Digits)
                     );
         }
      }  // for(int i = 0; i < VTRADENUM_MAX; i++) {
   } // if(fileHandle1 != INVALID_HANDLE){
   else {
      printf("[%d]ファイルオープンエラー：仮想取引", __LINE__);
      Print(GetLastError());
   }

   FileClose(fileHandle1);
}

//
// 平均と偏差計算用データを格納するグローバル変数
//
// トレンド分析
// 1 移動平均:MA
int MA_GC_mData[VTRADENUM_MAX];
int MA_DC_mData[VTRADENUM_MAX];
double MA_Slope5_mData[VTRADENUM_MAX];
double MA_Slope25_mData[VTRADENUM_MAX];
double MA_Slope75_mData[VTRADENUM_MAX];
// 2 ボリンジャーバンドBB
double BB_Width_mData[VTRADENUM_MAX];
// 3 一目均衡表:IK
double IK_TEN_mData[VTRADENUM_MAX];
double IK_CHI_mData[VTRADENUM_MAX];
double IK_LEG_mData[VTRADENUM_MAX];
// 4 MACD:MACD
int MACD_GC_mData[VTRADENUM_MAX];
int MACD_DC_mData[VTRADENUM_MAX];
//
// オシレーター分析
// 1 RSI:RSI
double RSI_VAL_mData[VTRADENUM_MAX];
// 2 ストキャスティクス:STOC
double STOC_VAL_mData[VTRADENUM_MAX];
double STOC_GC_mData[VTRADENUM_MAX];
double STOC_DC_mData[VTRADENUM_MAX];
// 4 RCI:RCI
double RCI_VAL_mData[VTRADENUM_MAX];

// トレンド分析
// 1 移動平均:MA
int MA_GC_mDataNum = 0;
int MA_DC_mDataNum = 0;
int MA_Slope5_mDataNum = 0;
int MA_Slope25_mDataNum = 0;
int MA_Slope75_mDataNum = 0;
// 2 ボリンジャーバンドBB
int BB_Width_mDataNum = 0;
// 3 一目均衡表:IK
int  IK_TEN_mDataNum = 0;
int IK_CHI_mDataNum = 0;
int IK_LEG_mDataNum = 0;
// 4 MACD:MACD
int MACD_GC_mDataNum = 0;
int MACD_DC_mDataNum = 0;
//
// オシレーター分析
// 1 RSI:RSI
int RSI_VAL_mDataNum = 0;
// 2 ストキャスティクス:STOC
int STOC_VAL_mDataNum = 0;
int STOC_GC_mDataNum = 0;
int STOC_DC_mDataNum = 0;
// 4 RCI:RCI
int RCI_VAL_mDataNum = 0;
//+-----------------------------------------------------------------------------+
//| 仮想取引を評価し、戦略別・通貨ペア別・タイムフレーム別・売買区分別・損益別の各指標の平均と偏差を計算する。      |
//+-----------------------------------------------------------------------------+
// ※評価対象となる仮想取引は、引数を約定時間にものに限定する。
// 4つの計算のうち、1つでも失敗したら、falseを返す。
bool create_st_vAnalyzedIndex(string strategyID,
                     string symbol,                 // 入力：EURUSD-CDなど
                     int    timeframe,              // 入力：時間軸。0は不可。PERIOD_M1～PERIOD_MN1
                     datetime mCalcTime,            // 計算基準時間
                     datetime FROM_vOrder_openTime, // 入力：評価対象となる仮想取引の約定時間がこの値以降。
                     datetime TO_vOrder_openTime    // 入力：評価対象となる仮想取引の約定時間がこの値以前。
                    )  {

//
//
// 仮想取引全てを、買い＋利益、買い＋損失、売り＋利益、売り＋損失の4つに分類して、
// それぞれの指標データの平均と偏差をグローバル変数に格納する。
//
//

   bool mFlag = false;
   bool ret = true; // 

   mFlag = create_Stoc_vOrdersBUY_PROFIT(strategyID, symbol, timeframe, mCalcTime, FROM_vOrder_openTime, TO_vOrder_openTime);
   if(mFlag == false) {
      ret = false;
   }
   mFlag = create_Stoc_vOrdersBUY_LOSS(strategyID, symbol, timeframe, mCalcTime, FROM_vOrder_openTime, TO_vOrder_openTime);
   if(mFlag == false) {
      ret = false;
   }

   mFlag = create_Stoc_vOrdersSELL_PROFIT(strategyID, symbol, timeframe, mCalcTime, FROM_vOrder_openTime, TO_vOrder_openTime);
   if(mFlag == false) {
      ret = false;
   }

   mFlag = create_Stoc_vOrdersSELL_LOSS(strategyID, symbol, timeframe, mCalcTime, FROM_vOrder_openTime, TO_vOrder_openTime);
   if(mFlag == false) {
      ret = false;
   }

   return ret;
}


// 仮想取引を評価し、戦略別・通貨ペア別・タイムフレーム別・売買区分別・損益別の各指標の平均と偏差を計算する。
// 仮想取引が買い＋利益である時の指標の平均と偏差を計算する。
// 計算結果は、グローバル変数st_vAnalyzedIndexesBUY_Profitに入る。
double create_Stoc_vOrdersBUY_PROFIT_buf_mData[VTRADENUM_MAX];
bool create_Stoc_vOrdersBUY_PROFIT(string strategyID,
                               string symbol,                 // 入力：EURUSD-CDなど
                               int    timeframe,              // 入力：時間軸。0は不可。PERIOD_M1～PERIOD_MN1
                               datetime mCalcTime,            // 計算基準時間
                               datetime FROM_vOrder_openTime, // 入力：評価対象となる仮想取引の約定時間がこの値以降。
                               datetime TO_vOrder_openTime    // 入力：評価対象となる仮想取引の約定時間がこの値以前。
                              )  {

   // キー項目の初期化
   st_vAnalyzedIndexesBUY_Profit.strategyID  = "";
   st_vAnalyzedIndexesBUY_Profit.symbol      = "";
   st_vAnalyzedIndexesBUY_Profit.timeframe   = -1;
   st_vAnalyzedIndexesBUY_Profit.orderType   = -1;
   st_vAnalyzedIndexesBUY_Profit.PLFlag      = 0;
   st_vAnalyzedIndexesBUY_Profit.analyzeTime = 0;
                              
   if(StringLen(strategyID) <= 0) {
      return false;
   }
   if(StringLen(symbol) <= 0) {
      return false;
   }
   if(timeframe < 0) {
      return false;
   }


   // 対象とする最初の時間が負の場合は、仮想取引の先頭から計算対象とする。
   if(FROM_vOrder_openTime < 0) {
      FROM_vOrder_openTime = 0;
   }
   
   // 対象とする最後の時間が負の場合は、計算基準時間まで計算対象とする。
   if(TO_vOrder_openTime < 0)  {
      TO_vOrder_openTime = mCalcTime;
   }
   
   // 開始時間より終了時間が前の場合はfalseを返して終了する。
   if(TO_vOrder_openTime < FROM_vOrder_openTime)  {
      return false;
   }

   int i;
   int count;
   double criteriaBID = 0.0;
   double criteriaASK = 0.0;
   double outPL = 0.0;
   double outPLEstimate = 0.0;
   bool   calcFlag = false;
   int Index_of_st_vOrderIndexes = -1;
   double indexMean  = 0.0;
   double indexSigma = 0.0;

   bool retFlag = false;  // 1項目でも計算が成功すれば、true。＝最後までfalseであれば、全滅を意味する。
//
// １．買い　かつ　利益の仮想取引のオープン時各指標値は、ここから。
//
// 変数の初期化。平均と偏差を計算するための配列MA_GC_mData[i]などを初期化。
   initParams();

   criteriaBID = DOUBLE_VALUE_MIN;
   criteriaASK = DOUBLE_VALUE_MIN;
   calcFlag = false;
   Index_of_st_vOrderIndexes = INT_VALUE_MIN;
   count = 0;  // 買い　かつ　利益の仮想取引 の件数。
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }
      // ①戦略・通貨ペア・タイムフレーム・約定時間が引数の範囲内・(売買区分 = OP_BUY)の仮想取引に該当する仮想取引があれば、
      if(StringLen(st_vOrders[i].strategyID) > 0 && StringLen(strategyID) > 0 && StringCompare(st_vOrders[i].strategyID, strategyID, true) == 0
         && StringLen(st_vOrders[i].symbol) > 0 && StringLen(symbol) > 0 && StringCompare(st_vOrders[i].symbol, symbol, true) == 0
         && st_vOrders[i].timeframe == timeframe
         && st_vOrders[i].openTime >= FROM_vOrder_openTime
         && st_vOrders[i].openTime <= TO_vOrder_openTime
         && st_vOrders[i].orderType == OP_BUY) {
         // 仮想取引が、決済利益または評価利益を持っている場合
         if((st_vOrders[i].closeTime > 0  && (st_vOrders[i].closePL > 0.0 && st_vOrders[i].closePL != DOUBLE_VALUE_MIN))
            || (st_vOrders[i].closeTime == 0 && (st_vOrders[i].estimatePL > 0.0 && st_vOrders[i].estimatePL != DOUBLE_VALUE_MIN))
         ) {
            // ②戦略・通貨ペア・タイムフレーム・売買区分 = OP_BUYに加えて、約定日時をキーとして
            //   当時の指標を持つst_vOrderIndexes[i]を探す
            Index_of_st_vOrderIndexes = getIndex_of_st_vOrderIndexes(
                                        strategyID,
                                        symbol,
                                        timeframe,
                                        st_vOrders[i].openTime
                                                                    );
            // ③st_vOrderIndexes[Index_of_st_vOrderIndexes]の各指標値を、指標値別平均と偏差計算用配列に代入する
            if(Index_of_st_vOrderIndexes < 0) {
               // 仮想取引発注時の指標が見つからなかったため、当時の指標を再計算する。
               v_calcIndexes();
               Index_of_st_vOrderIndexes = getIndex_of_st_vOrderIndexes(
                                           strategyID,
                                           symbol,
                                           timeframe,
                                           st_vOrders[i].openTime
                                                                       );
               // 当時の指標を再計算したにもかかわらず、当時の平均と偏差が見つからなければ、エラー
               if(Index_of_st_vOrderIndexes < 0) {
                  printf("[%d]VT getIndex_of_st_vOrderIndexesによる指標検索に失敗。", __LINE__);
                  return false;
               }
            }

            bool flagGeneralRule = true;
            // ③の追加：各指標値に一般的に求められる特性（例　MA上昇傾向で買い。下降傾向で売りなど）を満たしているか。
            if(Index_of_st_vOrderIndexes >= 0) {
               flagGeneralRule = satisfyGeneralRules(st_vOrderIndexes[Index_of_st_vOrderIndexes], vBUY_PROFIT);
            }

            // ③st_vOrderIndexes[Index_of_st_vOrderIndexes]の各指標値を、指標値別平均と偏差計算用配列に代入する
            if(Index_of_st_vOrderIndexes >= 0 && flagGeneralRule == true) {
               MA_GC_mData[count]      = st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_GC;
               MA_DC_mData[count]      = st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_DC;
               MA_Slope5_mData[count]  = (NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_Slope5, global_Digits)) ;
               MA_Slope25_mData[count] = (NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_Slope25, global_Digits));
               MA_Slope75_mData[count] = (NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_Slope75, global_Digits));
               // 2 ボリンジャーバンドBB
               BB_Width_mData[count]   = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].BB_Width, global_Digits);
               // 3 一目均衡表:IK
               IK_TEN_mData[count]     = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].IK_TEN, global_Digits);
               IK_CHI_mData[count]     = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].IK_CHI, global_Digits);
               IK_LEG_mData[count]     = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].IK_LEG, global_Digits);
               // 4 MACD:MACD
               MACD_GC_mData[count]    = st_vOrderIndexes[Index_of_st_vOrderIndexes].MACD_GC;
               MACD_DC_mData[count]    = st_vOrderIndexes[Index_of_st_vOrderIndexes].MACD_DC;
               //
               // オシレーター分析
               // 1 RSI:RSI
               RSI_VAL_mData[count]    = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].RSI_VAL, global_Digits);
               // 2 ストキャスティクス:STOC
               STOC_VAL_mData[count]   = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].STOC_VAL, global_Digits);
               STOC_GC_mData[count]    = st_vOrderIndexes[Index_of_st_vOrderIndexes].STOC_GC;
               STOC_DC_mData[count]    = st_vOrderIndexes[Index_of_st_vOrderIndexes].STOC_DC;
               // 4 RCI:RCI
               RCI_VAL_mData[count]    = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].RCI_VAL, global_Digits);

               count++;

            }
            else {
            }
         }  // else if(outPL > 0.0 || outPLEstimate > 0.0)
      }     // ②戦略・通貨ペア・タイムフレーム・売買区分 = OP_BUYの仮想取引に該当する仮想取引があれば、
   }        // for(i = 0; i < VTRADENUM_MAX; i++)　＝　仮想取引全件の探索

   printf("[%d]VT BUY_PROFIT=%d件", __LINE__, count);
   int    buf_mDataNum;

// 計算対象とする仮想取引が3件以上に限り、以下を実行する。
   if(count >= 3){
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      // ⑥作成した指標値別平均と偏差計算用配列を引数として、
      //   関数Puer_STAT.calcMeanAndSigma(double &mData[], int mDataNum, double &mMean, double &mSigma) を使って、
      //   平均と偏差を計算する。

      // ⑦計算した平均と偏差を
      //   グローバル変数st_vAnalyzedIndex st_vAnalyzedIndexesBUY_Profit;  // 買いで利益が出た仮想取引を対象とした指標の分析結果。
      //   の各項目に代入する。
      st_vAnalyzedIndexesBUY_Profit.strategyID  = strategyID;
      st_vAnalyzedIndexesBUY_Profit.symbol      = symbol;
      st_vAnalyzedIndexesBUY_Profit.timeframe   = timeframe;
      st_vAnalyzedIndexesBUY_Profit.orderType   = OP_BUY;
      st_vAnalyzedIndexesBUY_Profit.PLFlag      = vPROFIT;
      st_vAnalyzedIndexesBUY_Profit.analyzeTime = mCalcTime;

      // デバッグ用ファイル出力
      //トレンド分析
      //1 移動平均:MA
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++){
         if(MA_GC_mData[i] <= INT_VALUE_MIN) {
            break;
         }
         if(MA_GC_mData[i] > INT_VALUE_MIN) {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(MA_GC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }
      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.MA_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MA_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MA_GC_SIGMA = DOUBLE_VALUE_MIN;
      }


      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MA_DC_mData[i] <= INT_VALUE_MIN) {
            break;
         }
         if(MA_DC_mData[i] > INT_VALUE_MIN) {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = MA_DC_mData[i];
            buf_mDataNum++;
         }
      }
      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.MA_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else{
         st_vAnalyzedIndexesBUY_Profit.MA_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MA_DC_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MA_Slope5_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(MA_Slope5_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = MA_Slope5_mData[i];
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
        /*
         printf("[%d]VT BUY_PROFIT calcMeanAndSigma終了 データ数=%d 平均=%s 偏差=%s",
                __LINE__, buf_mDataNum,
                DoubleToStr(indexMean),
                DoubleToStr(indexSigma));
         */
      }
      else {
         printf("[%d]VT BUY_PROFIT calcMeanAndSigma終了 計算失敗",
                __LINE__);
      }
      if(calcFlag == true)   {
         st_vAnalyzedIndexesBUY_Profit.MA_Slope5_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_Slope5_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MA_Slope5_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MA_Slope5_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MA_Slope25_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(MA_Slope25_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(MA_Slope25_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.MA_Slope25_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_Slope25_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MA_Slope25_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MA_Slope25_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MA_Slope75_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(MA_Slope75_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(MA_Slope75_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.MA_Slope75_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MA_Slope75_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MA_Slope75_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MA_Slope75_SIGMA = DOUBLE_VALUE_MIN;
      }


      //2 ボリンジャーバンドBB
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(BB_Width_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(BB_Width_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(BB_Width_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.BB_Width_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.BB_Width_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.BB_Width_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.BB_Width_SIGMA = DOUBLE_VALUE_MIN;
      }

      //3 一目均衡表:IK
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(IK_TEN_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(IK_TEN_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(IK_TEN_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, count, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.IK_TEN_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.IK_TEN_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.IK_TEN_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.IK_TEN_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(IK_CHI_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(IK_CHI_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(IK_CHI_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.IK_CHI_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.IK_CHI_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.IK_CHI_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.IK_CHI_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(IK_LEG_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(IK_LEG_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(IK_LEG_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.IK_LEG_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.IK_LEG_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.IK_LEG_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.IK_LEG_SIGMA = DOUBLE_VALUE_MIN;
      }



      //4 MACD:MACD
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MACD_GC_mData[i] <= INT_VALUE_MIN)  {
            break;
         }
         if(MACD_GC_mData[i] > INT_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(MACD_GC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.MACD_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MACD_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MACD_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MACD_GC_SIGMA = DOUBLE_VALUE_MIN;
      }


      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MACD_DC_mData[i] <= INT_VALUE_MIN){
            break;
         }
         if(MACD_DC_mData[i] > INT_VALUE_MIN){
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(MACD_DC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.MACD_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.MACD_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.MACD_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.MACD_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
      //
      //オシレーター分析
      //1 RSI:RSI
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(RSI_VAL_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(RSI_VAL_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(RSI_VAL_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.RSI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.RSI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesBUY_Profit.RSI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.RSI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }

      //2 ストキャスティクス:STOC
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++){
         if(STOC_VAL_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(STOC_VAL_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(STOC_VAL_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.STOC_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.STOC_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else{
         st_vAnalyzedIndexesBUY_Profit.STOC_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.STOC_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++){
         if(STOC_GC_mData[i] <= INT_VALUE_MIN) {
            break;
         }
         if(STOC_GC_mData[i] > INT_VALUE_MIN) {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(STOC_GC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.STOC_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.STOC_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Profit.STOC_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.STOC_GC_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(STOC_DC_mData[i] <= INT_VALUE_MIN) {
            break;
         }
         if(STOC_DC_mData[i] > INT_VALUE_MIN) {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(STOC_DC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.STOC_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.STOC_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Profit.STOC_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.STOC_DC_SIGMA = DOUBLE_VALUE_MIN;
      }

      //4 RCI:RCI
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(RCI_VAL_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(RCI_VAL_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersBUY_PROFIT_buf_mData[i] = NormalizeDouble(RCI_VAL_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesBUY_Profit.RCI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Profit.RCI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Profit.RCI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Profit.RCI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }

      // 検証用ファイル出力の終了処理。
   }
   else{
      printf("[%d]VT 買い　かつ　利益の仮想取引が%d件のため、平均と偏差計算失敗。", __LINE__, count);
      return false;
   }

//
// １．買い　かつ　利益の仮想取引のオープン時各指標値は、ここまで。
//
   if(retFlag == false) {  // 計算に成功した項目が1つもない場合は、falseを返す。
      return false;
   }
   
   return true;
  }




// 計算結果をグローバル変数st_vAnalyzedIndexesBUY_LOSSに代入する。
double create_Stoc_vOrdersBUY_buf_mData[VTRADENUM_MAX]; // 512KBの問題があるため、グローバル変数とした
bool create_Stoc_vOrdersBUY_LOSS(string strategyID,
                             string symbol,                 // 入力：EURUSD-CDなど
                             int    timeframe,              // 入力：時間軸。0は不可。PERIOD_M1～PERIOD_MN1
                             datetime mCalcTime,            // 計算基準時間
                             datetime FROM_vOrder_openTime, // 入力：評価対象となる仮想取引の約定時間がこの値以降。
                             datetime TO_vOrder_openTime    // 入力：評価対象となる仮想取引の約定時間がこの値以前。
                            )  {
   // キー項目の初期化
   st_vAnalyzedIndexesBUY_Loss.strategyID  = "";
   st_vAnalyzedIndexesBUY_Loss.symbol      = "";
   st_vAnalyzedIndexesBUY_Loss.timeframe   = -1;
   st_vAnalyzedIndexesBUY_Loss.orderType   = -1;
   st_vAnalyzedIndexesBUY_Loss.PLFlag      = 0;
   st_vAnalyzedIndexesBUY_Loss.analyzeTime = 0;
                            
   if(StringLen(strategyID) <= 0) {
      return false;
   }
   if(StringLen(symbol) <= 0) {
      return false;
   }
   if(timeframe < 0) {
      return false;
   }

   // 対象とする最初の時間が負の場合は、仮想取引の先頭から計算対象とする。
   if(FROM_vOrder_openTime < 0) {
      FROM_vOrder_openTime = 0;
   }
   
   // 対象とする最後の時間が負の場合は、計算基準時間まで計算対象とする。
   if(TO_vOrder_openTime < 0) {
      TO_vOrder_openTime = mCalcTime;
   }

   // 開始時間より終了時間が前の場合はfalseを返して終了する。
   if(TO_vOrder_openTime < FROM_vOrder_openTime)  {
      return false;
   }
     

   int i;
   int count;
   double criteriaBID = 0.0;
   double criteriaASK = 0.0;
   double outPL = 0.0;
   double outPLEstimate = 0.0;
   bool   calcFlag = false;
   int Index_of_st_vOrderIndexes = -1;
   double indexMean  = 0.0;
   double indexSigma = 0.0;

   bool retFlag = false;  // 1項目でも計算が成功すれば、true。＝最後までfalseであれば、全滅を意味する。
   

//
// 2．買い　かつ　損失の仮想取引のオープン時各指標値は、ここから。
//
// 変数の初期化。平均と偏差を計算するための配列MA_GC_mData[i]などを初期化。
   initParams();

   criteriaBID = DOUBLE_VALUE_MIN;
   criteriaASK = DOUBLE_VALUE_MIN;
   calcFlag = false;
   Index_of_st_vOrderIndexes = INT_VALUE_MIN;
   count = 0;  // 買い　かつ　損失の仮想取引 の件数。
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }

      // ①戦略・通貨ペア・タイムフレーム・売買区分 = OP_BUYの仮想取引に該当する仮想取引があれば、
      if(StringLen(st_vOrders[i].strategyID) > 0 && StringLen(strategyID) > 0 && StringCompare(st_vOrders[i].strategyID, strategyID, true) == 0
         && StringLen(st_vOrders[i].symbol) > 0 && StringLen(symbol) > 0 && StringCompare(st_vOrders[i].symbol, symbol, true) == 0
         && st_vOrders[i].timeframe == timeframe
         && st_vOrders[i].openTime >= FROM_vOrder_openTime
         && st_vOrders[i].openTime <= TO_vOrder_openTime
         && st_vOrders[i].orderType == OP_BUY)  {
         // 買い仮想取引が、決済損失または評価損失を持っている場合

         if((st_vOrders[i].closeTime > 0  && (st_vOrders[i].closePL < 0.0 && st_vOrders[i].closePL != DOUBLE_VALUE_MIN))
            || (st_vOrders[i].closeTime == 0 && (st_vOrders[i].estimatePL < 0.0 && st_vOrders[i].estimatePL != DOUBLE_VALUE_MIN))
           ) {
            // ②戦略・通貨ペア・タイムフレーム・売買区分 = OP_BUYに加えて、約定日時をキーとして
            //   当時の指標を持つst_vOrderIndexes[i]を探す
            Index_of_st_vOrderIndexes = getIndex_of_st_vOrderIndexes(
                                        strategyID,
                                        symbol,
                                        timeframe,
                                        st_vOrders[i].openTime
                                                                    );
            // ③st_vOrderIndexes[Index_of_st_vOrderIndexes]の各指標値を、指標値別平均と偏差計算用配列に代入する
            if(Index_of_st_vOrderIndexes < 0)  {
               // 仮想取引発注時の指標が見つからなかったため、当時の指標を再計算する。
               v_calcIndexes();
               Index_of_st_vOrderIndexes = getIndex_of_st_vOrderIndexes(
                                           strategyID,
                                           symbol,
                                           timeframe,
                                           st_vOrders[i].openTime
                                                                       );
               // 当時の指標を再計算したにもかかわらず、当時の平均と偏差が見つからなければ、エラー
               if(Index_of_st_vOrderIndexes < 0)  {
                  printf("[%d]VT getIndex_of_st_vOrderIndexesによる指標検索に失敗。", __LINE__);
                  return false;                  
               }
            }

            bool flagGeneralRule = true;
            if(Index_of_st_vOrderIndexes >= 0) {
               flagGeneralRule = satisfyGeneralRules(st_vOrderIndexes[Index_of_st_vOrderIndexes], vBUY_LOSS);
            }
                        
            // ③st_vOrderIndexes[Index_of_st_vOrderIndexes]の各指標値を、指標値別平均と偏差計算用配列に代入する
            if(Index_of_st_vOrderIndexes >= 0 && flagGeneralRule == true)  {
               MA_GC_mData[count] = st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_GC;
               MA_DC_mData[count] = st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_DC;
               MA_Slope5_mData[count]  = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_Slope5, global_Digits) ;
               MA_Slope25_mData[count] = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_Slope25, global_Digits);
               MA_Slope75_mData[count] = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_Slope75, global_Digits);
               // 2 ボリンジャーバンドBB
               BB_Width_mData[count]   = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].BB_Width, global_Digits);
               // 3 一目均衡表:IK
               IK_TEN_mData[count]    = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].IK_TEN, global_Digits);
               IK_CHI_mData[count]    = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].IK_CHI, global_Digits);
               IK_LEG_mData[count]    = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].IK_LEG, global_Digits);
               // 4 MACD:MACD
               MACD_GC_mData[count]   = st_vOrderIndexes[Index_of_st_vOrderIndexes].MACD_GC;
               MACD_DC_mData[count]   = st_vOrderIndexes[Index_of_st_vOrderIndexes].MACD_DC;
               //
               // オシレーター分析
               // 1 RSI:RSI
               RSI_VAL_mData[count]   = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].RSI_VAL, global_Digits);
               // 2 ストキャスティクス:STOC
               STOC_VAL_mData[count]  = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].STOC_VAL, global_Digits);
               STOC_GC_mData[count]   = st_vOrderIndexes[Index_of_st_vOrderIndexes].STOC_GC;
               STOC_DC_mData[count]   = st_vOrderIndexes[Index_of_st_vOrderIndexes].STOC_DC;
               // 4 RCI:RCI
               RCI_VAL_mData[count]   = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].RCI_VAL, global_Digits);

               count++;
            }
            else  {
            }
         }  // else if(outPL > 0.0 || outPLEstimate > 0.0)
      }     // ②戦略・通貨ペア・タイムフレーム・売買区分 = OP_BUYの仮想取引に該当する仮想取引があれば、
   }        // for(i = 0; i < VTRADENUM_MAX; i++)　＝　仮想取引全件の探索

   
   int    buf_mDataNum;

// 計算対象とする仮想取引が3件以上に限り、以下を実行する。
   if(count >= 3)  {
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      // ⑥作成した指標値別平均と偏差計算用配列を引数として、
      //   関数Puer_STAT.calcMeanAndSigma(double &mData[], int mDataNum, double &mMean, double &mSigma) を使って、
      //   平均と偏差を計算する。

      // ⑦計算した平均と偏差を
      //   グローバル変数st_vAnalyzedIndex st_vAnalyzedIndexesBUY_LOSS;  // 買いで利益が出た仮想取引を対象とした指標の分析結果。
      //   の各項目に代入する。
      st_vAnalyzedIndexesBUY_Loss.strategyID  = strategyID;
      st_vAnalyzedIndexesBUY_Loss.symbol      = symbol;
      st_vAnalyzedIndexesBUY_Loss.timeframe   = timeframe;
      st_vAnalyzedIndexesBUY_Loss.orderType   = OP_BUY;
      st_vAnalyzedIndexesBUY_Loss.PLFlag      = vLOSS;
      st_vAnalyzedIndexesBUY_Loss.analyzeTime = mCalcTime;

      // デバッグ用ファイル出力
//      int fileHandle1 = FileOpen("IndexDataBUY_LOSS.csv", FILE_WRITE | FILE_CSV,",");
      //トレンド分析
      //1 移動平均:MA
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(MA_GC_mData[i] <= INT_VALUE_MIN)  {
            break;
         }
         if(MA_GC_mData[i] > INT_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(MA_GC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.MA_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.MA_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MA_GC_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(MA_DC_mData[i] <= INT_VALUE_MIN)  {
            break;
         }
         if(MA_DC_mData[i] > INT_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = MA_DC_mData[i];
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.MA_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.MA_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MA_DC_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(MA_Slope5_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(MA_Slope5_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = MA_Slope5_mData[i];
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.MA_Slope5_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_Slope5_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.MA_Slope5_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MA_Slope5_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(MA_Slope25_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(MA_Slope25_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(MA_Slope25_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.MA_Slope25_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_Slope25_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.MA_Slope25_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MA_Slope25_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(MA_Slope75_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(MA_Slope75_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(MA_Slope75_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.MA_Slope75_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MA_Slope75_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.MA_Slope75_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MA_Slope75_SIGMA = DOUBLE_VALUE_MIN;
      }


      //2 ボリンジャーバンドBB
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(BB_Width_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;  
         }
         if(BB_Width_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(BB_Width_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.BB_Width_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.BB_Width_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.BB_Width_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.BB_Width_SIGMA = DOUBLE_VALUE_MIN;
      }

      //3 一目均衡表:IK
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(IK_TEN_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(IK_TEN_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(IK_TEN_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, count, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.IK_TEN_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.IK_TEN_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.IK_TEN_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.IK_TEN_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(IK_CHI_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(IK_CHI_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(IK_CHI_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.IK_CHI_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.IK_CHI_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.IK_CHI_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.IK_CHI_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(IK_LEG_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(IK_LEG_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(IK_LEG_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }
      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.IK_LEG_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.IK_LEG_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.IK_LEG_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.IK_LEG_SIGMA = DOUBLE_VALUE_MIN;
      }

      //4 MACD:MACD
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(MACD_GC_mData[i] <= INT_VALUE_MIN)  {
            break;
         }
         if(MACD_GC_mData[i] > INT_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(MACD_GC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }
      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.MACD_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MACD_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.MACD_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MACD_GC_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(MACD_DC_mData[i] <= INT_VALUE_MIN)  {
            break;
         }
         if(MACD_DC_mData[i] > INT_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(MACD_DC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }
      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.MACD_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.MACD_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.MACD_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.MACD_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
      //
      //オシレーター分析
      //1 RSI:RSI
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(RSI_VAL_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(RSI_VAL_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(RSI_VAL_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.RSI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.RSI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.RSI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.RSI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }

      //2 ストキャスティクス:STOC
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(STOC_VAL_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(STOC_VAL_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(STOC_VAL_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.STOC_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.STOC_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.STOC_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.STOC_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(STOC_GC_mData[i] <= INT_VALUE_MIN)  {
            break;
         }
         if(STOC_GC_mData[i] > INT_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(STOC_GC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.STOC_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.STOC_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.STOC_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.STOC_GC_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(STOC_DC_mData[i] <= INT_VALUE_MIN)  {
            break;
         }
         if(STOC_DC_mData[i] > INT_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(STOC_DC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.STOC_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.STOC_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.STOC_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.STOC_DC_SIGMA = DOUBLE_VALUE_MIN;
      }

      //4 RCI:RCI
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(RCI_VAL_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(RCI_VAL_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersBUY_buf_mData[i] = NormalizeDouble(RCI_VAL_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersBUY_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesBUY_Loss.RCI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesBUY_Loss.RCI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesBUY_Loss.RCI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesBUY_Loss.RCI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }

      // 検証用ファイル出力の終了処理。
//      FileClose(fileHandle1);

      /*
      printf( "[%d]VT 買い　かつ　損失の平均と偏差計算結果" , __LINE__);
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.strategyID = %s", __LINE__, st_vAnalyzedIndexesBUY_Loss.strategyID );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.symbol = %s", __LINE__, st_vAnalyzedIndexesBUY_Loss.symbol);
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.timeframe = %d", __LINE__, st_vAnalyzedIndexesBUY_Loss.timeframe);
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.orderType = %d", __LINE__, st_vAnalyzedIndexesBUY_Loss.orderType);
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.PLFlag = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.PLFlag) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.analyzeTime = %s", __LINE__, TimeToStr(st_vAnalyzedIndexesBUY_Loss.analyzeTime) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MA_GC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MA_GC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MA_GC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MA_GC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MA_DC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MA_DC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MA_DC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MA_DC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MA_Slope5_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MA_Slope5_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MA_Slope5_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MA_Slope5_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MA_Slope25_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MA_Slope25_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MA_Slope25_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MA_Slope25_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MA_Slope75_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MA_Slope75_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MA_Slope75_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MA_Slope75_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.BB_Width_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.BB_Width_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.BB_Width_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.BB_Width_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.IK_TEN_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.IK_TEN_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.IK_TEN_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.IK_TEN_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.IK_CHI_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.IK_CHI_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.IK_CHI_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.IK_CHI_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.IK_LEG_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.IK_LEG_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.IK_LEG_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.IK_LEG_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MACD_GC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MACD_GC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MACD_GC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MACD_GC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MACD_DC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MACD_DC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.MACD_DC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.MACD_DC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.RSI_VAL_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.RSI_VAL_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.RSI_VAL_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.RSI_VAL_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.STOC_VAL_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.STOC_VAL_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.STOC_VAL_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.STOC_VAL_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.STOC_GC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.STOC_GC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.STOC_GC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.STOC_GC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.STOC_DC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.STOC_DC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.STOC_DC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.STOC_DC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.RCI_VAL_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.RCI_VAL_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesBUY_Loss.RCI_VAL_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesBUY_Loss.RCI_VAL_SIGMA) );
      */
     }
   else  {
      printf("[%d]VT 買い　かつ　損失の仮想取引が%d件のため、平均と偏差計算失敗。", __LINE__, count);
      return false;

   }


//
// 2．買い　かつ　損失の仮想取引のオープン時各指標値は、ここまで。
//
   if(retFlag == false) {  // 計算に成功した項目が1つもない場合は、falseを返す。
      return false;
   }

   return true;
}



// 計算結果をグローバル変数st_vAnalyzedIndexesSELL_Profitに代入する。
double create_Stoc_vOrdersSELL_PROFIT_buf_mData[VTRADENUM_MAX];
bool create_Stoc_vOrdersSELL_PROFIT(string strategyID,
                                string symbol,                 // 入力：EURUSD-CDなど
                                int    timeframe,              // 入力：時間軸。0は不可。PERIOD_M1～PERIOD_MN1
                                datetime mCalcTime,            // 計算基準時間
                                datetime FROM_vOrder_openTime, // 入力：評価対象となる仮想取引の約定時間がこの値以降。
                                datetime TO_vOrder_openTime    // 入力：評価対象となる仮想取引の約定時間がこの値以前。
                               )  {
   // キー項目の初期化
   st_vAnalyzedIndexesSELL_Profit.strategyID  = "";
   st_vAnalyzedIndexesSELL_Profit.symbol      = "";
   st_vAnalyzedIndexesSELL_Profit.timeframe   = -1;
   st_vAnalyzedIndexesSELL_Profit.orderType   = -1;
   st_vAnalyzedIndexesSELL_Profit.PLFlag      = 0;
   st_vAnalyzedIndexesSELL_Profit.analyzeTime = 0;

   if(StringLen(strategyID) <= 0)
     {
      return false;
     }
   if(StringLen(symbol) <= 0)
     {
      return false;
     }
   if(timeframe < 0)
     {
      return false;
     }

   // 対象とする最初の時間が負の場合は、仮想取引の先頭から計算対象とする。
   if(FROM_vOrder_openTime < 0)
     {
      FROM_vOrder_openTime = 0;
     }
   
   // 対象とする最後の時間が負の場合は、計算基準時間まで計算対象とする。
   if(TO_vOrder_openTime < 0)
     {
      TO_vOrder_openTime = mCalcTime;
     }

   // 開始時間より終了時間が前の場合はfalseを返して終了する。
   if(TO_vOrder_openTime < FROM_vOrder_openTime)  {
      return false;
   }

   int i;
   int count;
   double criteriaBID = 0.0;
   double criteriaASK = 0.0;
   double outPL = 0.0;
   double outPLEstimate = 0.0;
   bool   calcFlag = false;
   int Index_of_st_vOrderIndexes = -1;
   double indexMean  = 0.0;
   double indexSigma = 0.0;

   bool retFlag = false;  // 1項目でも計算が成功すれば、true。＝最後までfalseであれば、全滅を意味する。
   

//
// 3．売り　かつ　利益の仮想取引のオープン時各指標値は、ここから。
//
// 変数の初期化。平均と偏差を計算するための配列MA_GC_mData[i]などを初期化。
   initParams();


   criteriaBID = DOUBLE_VALUE_MIN;
   criteriaASK = DOUBLE_VALUE_MIN;
   calcFlag = false;
   Index_of_st_vOrderIndexes = INT_VALUE_MIN;
   count = 0;  // 売り　かつ　利益の仮想取引 の件数。
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }

      // ①戦略・通貨ペア・タイムフレーム・売買区分 = OP_SELLの仮想取引に該当する仮想取引があれば、
      if(StringLen(st_vOrders[i].strategyID) > 0 && StringLen(strategyID) > 0 && StringCompare(st_vOrders[i].strategyID, strategyID, true) == 0
         && StringLen(st_vOrders[i].symbol) > 0 && StringLen(symbol) > 0 && StringCompare(st_vOrders[i].symbol, symbol, true) == 0
         && st_vOrders[i].timeframe == timeframe
         && st_vOrders[i].openTime >= FROM_vOrder_openTime
         && st_vOrders[i].openTime <= TO_vOrder_openTime
         && st_vOrders[i].orderType == OP_SELL)
        {

         if((st_vOrders[i].closeTime > 0  && (st_vOrders[i].closePL > 0.0 && st_vOrders[i].closePL != DOUBLE_VALUE_MIN))
            || (st_vOrders[i].closeTime == 0 && (st_vOrders[i].estimatePL > 0.0 && st_vOrders[i].estimatePL != DOUBLE_VALUE_MIN))
           )  {
            // ②戦略・通貨ペア・タイムフレーム・売買区分 = OP_SELLに加えて、約定日時をキーとして
            //   当時の指標を持つst_vOrderIndexes[i]を探す
            Index_of_st_vOrderIndexes = getIndex_of_st_vOrderIndexes(strategyID,
                                        symbol,
                                        timeframe,
                                        st_vOrders[i].openTime
                                                                    );
            // ③st_vOrderIndexes[Index_of_st_vOrderIndexes]の各指標値を、指標値別平均と偏差計算用配列に代入する
            if(Index_of_st_vOrderIndexes < 0) {
               // 仮想取引発注時の指標が見つからなかったため、当時の指標を再計算する。
               v_calcIndexes();
               Index_of_st_vOrderIndexes = getIndex_of_st_vOrderIndexes(strategyID,
                                           symbol,
                                           timeframe,
                                           st_vOrders[i].openTime
                                                                       );
               // 当時の指標を再計算したにもかかわらず、当時の平均と偏差が見つからなければ、エラー
               if(Index_of_st_vOrderIndexes < 0) {
                  printf("[%d]VT getIndex_of_st_vOrderIndexesによる指標検索に失敗。", __LINE__);
                  return false; 
               }
            }

            bool flagGeneralRule = true;
            if(Index_of_st_vOrderIndexes >= 0) {
               flagGeneralRule = satisfyGeneralRules(st_vOrderIndexes[Index_of_st_vOrderIndexes], vSELL_PROFIT);
            }
                       
            // ③st_vOrderIndexes[Index_of_st_vOrderIndexes]の各指標値を、指標値別平均と偏差計算用配列に代入する
            if(Index_of_st_vOrderIndexes >= 0 && flagGeneralRule == true) {
               MA_GC_mData[count]      = st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_GC;
               MA_DC_mData[count]      = st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_DC;
               MA_Slope5_mData[count]  = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_Slope5, global_Digits)  ;
               MA_Slope25_mData[count] = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_Slope25, global_Digits) ;
               MA_Slope75_mData[count] = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_Slope75, global_Digits) ;
               // 2 ボリンジャーバンドBB
               BB_Width_mData[count]   = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].BB_Width, global_Digits);
               // 3 一目均衡表:IK
               IK_TEN_mData[count]     = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].IK_TEN, global_Digits);
               IK_CHI_mData[count]     = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].IK_CHI, global_Digits);
               IK_LEG_mData[count]     = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].IK_LEG, global_Digits);
               // 4 MACD:MACD
               MACD_GC_mData[count]    = st_vOrderIndexes[Index_of_st_vOrderIndexes].MACD_GC;
               MACD_DC_mData[count]    = st_vOrderIndexes[Index_of_st_vOrderIndexes].MACD_DC;
               //
               // オシレーター分析
               // 1 RSI:RSI
               RSI_VAL_mData[count]    = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].RSI_VAL, global_Digits);
               // 2 ストキャスティクス:STOC
               STOC_VAL_mData[count]   = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].STOC_VAL, global_Digits);
               STOC_GC_mData[count]    = st_vOrderIndexes[Index_of_st_vOrderIndexes].STOC_GC;
               STOC_DC_mData[count]    = st_vOrderIndexes[Index_of_st_vOrderIndexes].STOC_DC;
               // 4 RCI:RCI
               RCI_VAL_mData[count]    = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].RCI_VAL, global_Digits);

               count++;

              }
            else
              {
              }
           }  // else if(outPL > 0.0 || outPLEstimate > 0.0)
        }     // ②戦略・通貨ペア・タイムフレーム・売買区分 = OP_SELLの仮想取引に該当する仮想取引があれば、
     }        // for(i = 0; i < VTRADENUM_MAX; i++)　＝　仮想取引全件の探索

   printf("[%d]VT SELL_PROFIT=%d件", __LINE__, count);


   int    buf_mDataNum;

// 計算対象とする仮想取引が3件以上に限り、以下を実行する。
   if(count >= 3) {
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      // ⑥作成した指標値別平均と偏差計算用配列を引数として、
      //   関数Puer_STAT.calcMeanAndSigma(double &mData[], int mDataNum, double &mMean, double &mSigma) を使って、
      //   平均と偏差を計算する。
      // ⑦計算した平均と偏差を
      //   グローバル変数st_vAnalyzedIndex st_vAnalyzedIndexesSELL_Profit;  // 売りで利益が出た仮想取引を対象とした指標の分析結果。
      //   の各項目に代入する。
      st_vAnalyzedIndexesSELL_Profit.strategyID  = strategyID;
      st_vAnalyzedIndexesSELL_Profit.symbol      = symbol;
      st_vAnalyzedIndexesSELL_Profit.timeframe   = timeframe;
      st_vAnalyzedIndexesSELL_Profit.orderType   = OP_SELL;
      st_vAnalyzedIndexesSELL_Profit.PLFlag      = vPROFIT;
      st_vAnalyzedIndexesSELL_Profit.analyzeTime = mCalcTime;

      // デバッグ用ファイル出力
      //トレンド分析
      //1 移動平均:MA
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MA_GC_mData[i] > INT_VALUE_MIN) {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(MA_GC_mData[i], global_Digits);
            buf_mDataNum++;
           }
        }
      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesSELL_Profit.MA_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.MA_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MA_GC_SIGMA = DOUBLE_VALUE_MIN;
      }


      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MA_DC_mData[i] <= INT_VALUE_MIN) {
            break;
         }
         if(MA_DC_mData[i] > INT_VALUE_MIN) {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = MA_DC_mData[i];
            buf_mDataNum++;
         }
      }
      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesSELL_Profit.MA_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.MA_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MA_DC_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MA_Slope5_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(MA_Slope5_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = MA_Slope5_mData[i];
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesSELL_Profit.MA_Slope5_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_Slope5_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.MA_Slope5_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MA_Slope5_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MA_Slope25_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }  
         if(MA_Slope25_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(MA_Slope25_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesSELL_Profit.MA_Slope25_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_Slope25_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesSELL_Profit.MA_Slope25_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MA_Slope25_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(MA_Slope75_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(MA_Slope75_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(MA_Slope75_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesSELL_Profit.MA_Slope75_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MA_Slope75_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.MA_Slope75_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MA_Slope75_SIGMA = DOUBLE_VALUE_MIN;
      }


      //2 ボリンジャーバンドBB
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(BB_Width_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(BB_Width_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesSELL_Profit.BB_Width_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.BB_Width_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.BB_Width_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.BB_Width_SIGMA = DOUBLE_VALUE_MIN;
      }

      //3 一目均衡表:IK
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(IK_TEN_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(IK_TEN_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(IK_TEN_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, count, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesSELL_Profit.IK_TEN_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.IK_TEN_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.IK_TEN_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.IK_TEN_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(IK_CHI_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(IK_CHI_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(IK_CHI_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesSELL_Profit.IK_CHI_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.IK_CHI_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.IK_CHI_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.IK_CHI_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(IK_LEG_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(IK_LEG_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(IK_LEG_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesSELL_Profit.IK_LEG_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.IK_LEG_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.IK_LEG_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.IK_LEG_SIGMA = DOUBLE_VALUE_MIN;
      }

      //4 MACD:MACD
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(MACD_GC_mData[i] <= INT_VALUE_MIN)  {
            break;
         }
         if(MACD_GC_mData[i] > INT_VALUE_MIN)  {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(MACD_GC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesSELL_Profit.MACD_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MACD_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else    {
         st_vAnalyzedIndexesSELL_Profit.MACD_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MACD_GC_SIGMA = DOUBLE_VALUE_MIN;
      }


      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(MACD_DC_mData[i] <= INT_VALUE_MIN) {
            break;
         }
         if(MACD_DC_mData[i] > INT_VALUE_MIN) {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(MACD_DC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)   {
         st_vAnalyzedIndexesSELL_Profit.MACD_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.MACD_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Profit.MACD_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.MACD_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
      //
      //オシレーター分析
      //1 RSI:RSI
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(RSI_VAL_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(RSI_VAL_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(RSI_VAL_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesSELL_Profit.RSI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.RSI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else   {
         st_vAnalyzedIndexesSELL_Profit.RSI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.RSI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }

      //2 ストキャスティクス:STOC
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(STOC_VAL_mData[i] <= DOUBLE_VALUE_MIN)   {
            break;
         }
         if(STOC_VAL_mData[i] > DOUBLE_VALUE_MIN)   {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(STOC_VAL_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesSELL_Profit.STOC_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.STOC_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true; 
      }
      else     {
         st_vAnalyzedIndexesSELL_Profit.STOC_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.STOC_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(STOC_GC_mData[i] <= INT_VALUE_MIN)  {
            break;
         }
         if(STOC_GC_mData[i] > INT_VALUE_MIN)  {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(STOC_GC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)   {
         st_vAnalyzedIndexesSELL_Profit.STOC_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.STOC_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else    {
         st_vAnalyzedIndexesSELL_Profit.STOC_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.STOC_GC_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)   {
         if(STOC_DC_mData[i] <= INT_VALUE_MIN){
            break;
         }
         if(STOC_DC_mData[i] > INT_VALUE_MIN){
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(STOC_DC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesSELL_Profit.STOC_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.STOC_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;
      }
      else  {
         st_vAnalyzedIndexesSELL_Profit.STOC_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.STOC_DC_SIGMA = DOUBLE_VALUE_MIN;
      }

      //4 RCI:RCI
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(RCI_VAL_mData[i] > DOUBLE_VALUE_MIN) {
            break;
         }
         if(RCI_VAL_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersSELL_PROFIT_buf_mData[i] = NormalizeDouble(RCI_VAL_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_PROFIT_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)  {
         st_vAnalyzedIndexesSELL_Profit.RCI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Profit.RCI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true; 
      }
      else  {
         st_vAnalyzedIndexesSELL_Profit.RCI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Profit.RCI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }

      // 検証用ファイル出力の終了処理。
//      FileClose(fileHandle1);

      /*
      printf( "[%d]VT 売り　かつ　利益の平均と偏差計算結果" , __LINE__);
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.strategyID = %s", __LINE__, st_vAnalyzedIndexesSELL_Profit.strategyID );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.symbol = %s", __LINE__, st_vAnalyzedIndexesSELL_Profit.symbol);
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.timeframe = %d", __LINE__, st_vAnalyzedIndexesSELL_Profit.timeframe);
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.orderType = %d", __LINE__, st_vAnalyzedIndexesSELL_Profit.orderType);
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.PLFlag = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.PLFlag) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.analyzeTime = %s", __LINE__, TimeToStr(st_vAnalyzedIndexesSELL_Profit.analyzeTime) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MA_GC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MA_GC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MA_GC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MA_GC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MA_DC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MA_DC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MA_DC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MA_DC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MA_Slope5_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MA_Slope5_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MA_Slope5_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MA_Slope5_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MA_Slope25_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MA_Slope25_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MA_Slope25_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MA_Slope25_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MA_Slope75_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MA_Slope75_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MA_Slope75_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MA_Slope75_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.BB_Width_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.BB_Width_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.BB_Width_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.BB_Width_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.IK_TEN_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.IK_TEN_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.IK_TEN_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.IK_TEN_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.IK_CHI_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.IK_CHI_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.IK_CHI_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.IK_CHI_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.IK_LEG_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.IK_LEG_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.IK_LEG_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.IK_LEG_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MACD_GC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MACD_GC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MACD_GC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MACD_GC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MACD_DC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MACD_DC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.MACD_DC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.MACD_DC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.RSI_VAL_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.RSI_VAL_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.RSI_VAL_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.RSI_VAL_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.STOC_VAL_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.STOC_VAL_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.STOC_VAL_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.STOC_VAL_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.STOC_GC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.STOC_GC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.STOC_GC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.STOC_GC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.STOC_DC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.STOC_DC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.STOC_DC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.STOC_DC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.RCI_VAL_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.RCI_VAL_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Profit.RCI_VAL_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Profit.RCI_VAL_SIGMA) );
      */
     }
   else
     {
      printf("[%d]VT 売り　かつ　利益の仮想取引が%d件のため、平均と偏差計算失敗。", __LINE__, count);
      return false;

     }


//
// 3．売り　かつ　利益の仮想取引のオープン時各指標値は、ここまで。
//
   if(retFlag == false) {  // 計算に成功した項目が1つもない場合は、falseを返す。
      return false;
   }

   return true;
}




// 計算結果をグローバル変数st_vAnalyzedIndexesSELL_Lossに代入する。
double create_Stoc_vOrdersSELL_LOSS_buf_mData[VTRADENUM_MAX];
bool create_Stoc_vOrdersSELL_LOSS(string strategyID,
                              string symbol,                 // 入力：EURUSD-CDなど
                              int    timeframe,              // 入力：時間軸。0は不可。PERIOD_M1～PERIOD_MN1
                              datetime mCalcTime,            // 計算基準時間
                              datetime FROM_vOrder_openTime, // 入力：評価対象となる仮想取引の約定時間がこの値以降。
                              datetime TO_vOrder_openTime    // 入力：評価対象となる仮想取引の約定時間がこの値以前。
                             )  {
   // キー項目の初期化
   st_vAnalyzedIndexesSELL_Loss.strategyID  = "";
   st_vAnalyzedIndexesSELL_Loss.symbol      = "";
   st_vAnalyzedIndexesSELL_Loss.timeframe   = -1;
   st_vAnalyzedIndexesSELL_Loss.orderType   = -1;
   st_vAnalyzedIndexesSELL_Loss.PLFlag      = 0;
   st_vAnalyzedIndexesSELL_Loss.analyzeTime = 0;
                             
   if(StringLen(strategyID) <= 0) {
      return false;
   }
   if(StringLen(symbol) <= 0) {
      return false;
   }
   if(timeframe < 0) {
      return false;
   }
     

   // 対象とする最初の時間が負の場合は、仮想取引の先頭から計算対象とする。
   if(FROM_vOrder_openTime < 0)  {
      FROM_vOrder_openTime = 0;
   }

   // 対象とする最後の時間が負の場合は、計算基準時間まで計算対象とする。
   if(TO_vOrder_openTime < 0)  {
      TO_vOrder_openTime = mCalcTime;
   }

   // 開始時間より終了時間が前の場合はfalseを返して終了する。
   if(TO_vOrder_openTime < FROM_vOrder_openTime)  {
      return false;
   }

   int i;
   int count;
   double criteriaBID = 0.0;
   double criteriaASK = 0.0;
   double outPL = 0.0;
   double outPLEstimate = 0.0;
   bool   calcFlag = false;
   int Index_of_st_vOrderIndexes = -1;
   double indexMean  = 0.0;
   double indexSigma = 0.0;

   bool retFlag = false;  // 1項目でも計算が成功すれば、true。＝最後までfalseであれば、全滅を意味する。
   

//
// 4．売り　かつ　損失の仮想取引のオープン時各指標値は、ここから。
//
// 変数の初期化。平均と偏差を計算するための配列MA_GC_mData[i]などを初期化。
   initParams();

   criteriaBID = DOUBLE_VALUE_MIN;
   criteriaASK = DOUBLE_VALUE_MIN;
   calcFlag = false;
   Index_of_st_vOrderIndexes = INT_VALUE_MIN;
   count = 0;  // 売り　かつ　損失の仮想取引 の件数。
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }

      // ①戦略・通貨ペア・タイムフレーム・売買区分 = OP_SELLの仮想取引に該当する仮想取引があれば、
      if(StringLen(st_vOrders[i].strategyID) > 0 && StringLen(strategyID) > 0 && StringCompare(st_vOrders[i].strategyID, strategyID, true) == 0
         && StringLen(st_vOrders[i].symbol) > 0 && StringLen(symbol) > 0 && StringCompare(st_vOrders[i].symbol, symbol, true) == 0
         && st_vOrders[i].timeframe == timeframe
         && st_vOrders[i].openTime >= FROM_vOrder_openTime
         && st_vOrders[i].openTime <= TO_vOrder_openTime
         && st_vOrders[i].orderType == OP_SELL) {
         if((st_vOrders[i].closeTime > 0  && (st_vOrders[i].closePL < 0.0 && st_vOrders[i].closePL != DOUBLE_VALUE_MIN))
            || (st_vOrders[i].closeTime == 0 && (st_vOrders[i].estimatePL < 0.0 && st_vOrders[i].estimatePL != DOUBLE_VALUE_MIN))
           ) {
            // ②戦略・通貨ペア・タイムフレーム・売買区分 = OP_SELLに加えて、約定日時をキーとして
            //   当時の指標を持つst_vOrderIndexes[i]を探す
            Index_of_st_vOrderIndexes = getIndex_of_st_vOrderIndexes(strategyID,
                                        symbol,
                                        timeframe,
                                        st_vOrders[i].openTime
                                                                    );
            // ③st_vOrderIndexes[Index_of_st_vOrderIndexes]の各指標値を、指標値別平均と偏差計算用配列に代入する
            if(Index_of_st_vOrderIndexes < 0) {
               // 仮想取引発注時の指標が見つからなかったため、当時の指標を再計算する。
               v_calcIndexes();
               Index_of_st_vOrderIndexes = getIndex_of_st_vOrderIndexes(strategyID,
                                           symbol,
                                           timeframe,
                                           st_vOrders[i].openTime
                                                                       );
               // 当時の指標を再計算したにもかかわらず、当時の平均と偏差が見つからなければ、エラー
               if(Index_of_st_vOrderIndexes < 0) {
                  printf("[%d]VT getIndex_of_st_vOrderIndexesによる指標検索に失敗。", __LINE__);
                  return false; 
               }
            }

            bool flagGeneralRule = true;
            if(Index_of_st_vOrderIndexes >= 0) {
               flagGeneralRule = satisfyGeneralRules(st_vOrderIndexes[Index_of_st_vOrderIndexes], vSELL_LOSS);
            }
                       
            if(Index_of_st_vOrderIndexes >= 0 && flagGeneralRule == true)  {
               MA_GC_mData[count]      = st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_GC;
               MA_DC_mData[count]      = st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_DC;
               MA_Slope5_mData[count]  = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_Slope5, global_Digits)  ;
               MA_Slope25_mData[count] = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_Slope25, global_Digits) ;
               MA_Slope75_mData[count] = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].MA_Slope75, global_Digits) ;
               // 2 ボリンジャーバンドBB
               BB_Width_mData[count]   = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].BB_Width, global_Digits);
               // 3 一目均衡表:IK
               IK_TEN_mData[count]     = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].IK_TEN, global_Digits);
               IK_CHI_mData[count]     = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].IK_CHI, global_Digits);
               IK_LEG_mData[count]     = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].IK_LEG, global_Digits);
               // 4 MACD:MACD
               MACD_GC_mData[count]    = st_vOrderIndexes[Index_of_st_vOrderIndexes].MACD_GC;
               MACD_DC_mData[count]    = st_vOrderIndexes[Index_of_st_vOrderIndexes].MACD_DC;
               //
               // オシレーター分析
               // 1 RSI:RSI
               RSI_VAL_mData[count]    = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].RSI_VAL, global_Digits);
               // 2 ストキャスティクス:STOC
               STOC_VAL_mData[count]   = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].STOC_VAL, global_Digits);
               STOC_GC_mData[count]    = st_vOrderIndexes[Index_of_st_vOrderIndexes].STOC_GC;
               STOC_DC_mData[count]    = st_vOrderIndexes[Index_of_st_vOrderIndexes].STOC_DC;
               // 4 RCI:RCI
               RCI_VAL_mData[count]    = NormalizeDouble(st_vOrderIndexes[Index_of_st_vOrderIndexes].RCI_VAL, global_Digits);

               count++;
            }
            else {
            }
         }  // else if(outPL > 0.0 || outPLEstimate > 0.0)
      }     // ②戦略・通貨ペア・タイムフレーム・売買区分 = OP_SELLの仮想取引に該当する仮想取引があれば、
   }        // for(i = 0; i < VTRADENUM_MAX; i++)　＝　仮想取引全件の探索

   printf("[%d]VT SELL_LOSS=%d件", __LINE__, count);


   int    buf_mDataNum;

// 計算対象とする仮想取引が3件以上に限り、以下を実行する。
   if(count >= 3) {
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      // ⑥作成した指標値別平均と偏差計算用配列を引数として、
      //   関数Puer_STAT.calcMeanAndSigma(double &mData[], int mDataNum, double &mMean, double &mSigma) を使って、
      //   平均と偏差を計算する。

      // ⑦計算した平均と偏差を
      //   グローバル変数st_vAnalyzedIndex st_vAnalyzedIndexesSELL_Loss;  // 売りで損失が出た仮想取引を対象とした指標の分析結果。
      //   の各項目に代入する。
      st_vAnalyzedIndexesSELL_Loss.strategyID  = strategyID;
      st_vAnalyzedIndexesSELL_Loss.symbol      = symbol;
      st_vAnalyzedIndexesSELL_Loss.timeframe   = timeframe;
      st_vAnalyzedIndexesSELL_Loss.orderType   = OP_SELL;
      st_vAnalyzedIndexesSELL_Loss.PLFlag      = vLOSS;
      st_vAnalyzedIndexesSELL_Loss.analyzeTime = mCalcTime;

      // デバッグ用ファイル出力
      //トレンド分析
      //1 移動平均:MA
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(MA_GC_mData[i] > INT_VALUE_MIN) {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(MA_GC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesSELL_Loss.MA_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.MA_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MA_GC_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(MA_DC_mData[i] <= INT_VALUE_MIN) {
            break;
         }
         if(MA_DC_mData[i] > INT_VALUE_MIN) {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = MA_DC_mData[i];
            buf_mDataNum++;
         }
      }


      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesSELL_Loss.MA_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.MA_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MA_DC_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MA_Slope5_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(MA_Slope5_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = MA_Slope5_mData[i];
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesSELL_Loss.MA_Slope5_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_Slope5_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.MA_Slope5_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MA_Slope5_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MA_Slope25_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(MA_Slope25_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(MA_Slope25_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true) {
         st_vAnalyzedIndexesSELL_Loss.MA_Slope25_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_Slope25_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.MA_Slope25_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MA_Slope25_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++) {
         if(MA_Slope75_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(MA_Slope75_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(MA_Slope75_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)   {
         st_vAnalyzedIndexesSELL_Loss.MA_Slope75_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MA_Slope75_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else   {
         st_vAnalyzedIndexesSELL_Loss.MA_Slope75_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MA_Slope75_SIGMA = DOUBLE_VALUE_MIN;
      }


      //2 ボリンジャーバンドBB
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(BB_Width_mData[i] <= DOUBLE_VALUE_MIN){
            break;
         }
         if(BB_Width_mData[i] > DOUBLE_VALUE_MIN){
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(BB_Width_mData[i], global_Digits);
            buf_mDataNum++;
           }
        }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)        {
         st_vAnalyzedIndexesSELL_Loss.BB_Width_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.BB_Width_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else   {
         st_vAnalyzedIndexesSELL_Loss.BB_Width_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.BB_Width_SIGMA = DOUBLE_VALUE_MIN;
      }

      //3 一目均衡表:IK
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)   {
         if(IK_TEN_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(IK_TEN_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(IK_TEN_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, count, indexMean, indexSigma);
      if(calcFlag == true)   {
         st_vAnalyzedIndexesSELL_Loss.IK_TEN_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.IK_TEN_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else       {
         st_vAnalyzedIndexesSELL_Loss.IK_TEN_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.IK_TEN_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)        {
         if(IK_CHI_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(IK_CHI_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(IK_CHI_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)     {
         st_vAnalyzedIndexesSELL_Loss.IK_CHI_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.IK_CHI_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else        {
         st_vAnalyzedIndexesSELL_Loss.IK_CHI_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.IK_CHI_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)        {
         if(IK_LEG_mData[i] <= DOUBLE_VALUE_MIN)    {
            break;
         }
         if(IK_LEG_mData[i] > DOUBLE_VALUE_MIN)    {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(IK_LEG_mData[i], global_Digits);
            buf_mDataNum++;
           }
        }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)        {
         st_vAnalyzedIndexesSELL_Loss.IK_LEG_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.IK_LEG_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else        {
         st_vAnalyzedIndexesSELL_Loss.IK_LEG_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.IK_LEG_SIGMA = DOUBLE_VALUE_MIN;
      }



      //4 MACD:MACD
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)        {
         if(MACD_GC_mData[i] <= INT_VALUE_MIN)  {
             break;
         }
         if(MACD_GC_mData[i] > INT_VALUE_MIN)       {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(MACD_GC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)      {
         st_vAnalyzedIndexesSELL_Loss.MACD_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MACD_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;
      }
      else        {
         st_vAnalyzedIndexesSELL_Loss.MACD_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MACD_GC_SIGMA = DOUBLE_VALUE_MIN;
      }


      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)        {
         if(MACD_DC_mData[i] <= INT_VALUE_MIN)     {
            break;
         }
         if(MACD_DC_mData[i] > INT_VALUE_MIN)     {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(MACD_DC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)      {
         st_vAnalyzedIndexesSELL_Loss.MACD_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.MACD_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else        {
         st_vAnalyzedIndexesSELL_Loss.MACD_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.MACD_DC_SIGMA = DOUBLE_VALUE_MIN;
      }
      //
      //オシレーター分析
      //1 RSI:RSI
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)  {
         if(RSI_VAL_mData[i] <= DOUBLE_VALUE_MIN) {
            break;
         }
         if(RSI_VAL_mData[i] > DOUBLE_VALUE_MIN) {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(RSI_VAL_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)      {
         st_vAnalyzedIndexesSELL_Loss.RSI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.RSI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else   {
         st_vAnalyzedIndexesSELL_Loss.RSI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.RSI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }

      //2 ストキャスティクス:STOC
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)        {
         if(STOC_VAL_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(STOC_VAL_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(STOC_VAL_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)      {
         st_vAnalyzedIndexesSELL_Loss.STOC_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.STOC_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesSELL_Loss.STOC_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.STOC_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)        {
         if(STOC_GC_mData[i] <= INT_VALUE_MIN) {
            break;
         }
         if(STOC_GC_mData[i] > INT_VALUE_MIN) {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(STOC_GC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)    {
         st_vAnalyzedIndexesSELL_Loss.STOC_GC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.STOC_GC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true; 
      }
      else {
         st_vAnalyzedIndexesSELL_Loss.STOC_GC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.STOC_GC_SIGMA = DOUBLE_VALUE_MIN;
      }

      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)   {
         if(STOC_DC_mData[i] <= INT_VALUE_MIN)  {
            break;
         }
         if(STOC_DC_mData[i] > INT_VALUE_MIN)  {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(STOC_DC_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)      {
         st_vAnalyzedIndexesSELL_Loss.STOC_DC_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.STOC_DC_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;  
      }
      else        {
         st_vAnalyzedIndexesSELL_Loss.STOC_DC_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.STOC_DC_SIGMA = DOUBLE_VALUE_MIN;
      }

      //4 RCI:RCI
      indexMean  = DOUBLE_VALUE_MIN;
      indexSigma = DOUBLE_VALUE_MIN;
      buf_mDataNum = 0;
      for(i = 0; i < VTRADENUM_MAX; i++)        {
         if(RCI_VAL_mData[i] <= DOUBLE_VALUE_MIN)  {
            break;
         }
         if(RCI_VAL_mData[i] > DOUBLE_VALUE_MIN)  {
            create_Stoc_vOrdersSELL_LOSS_buf_mData[i] = NormalizeDouble(RCI_VAL_mData[i], global_Digits);
            buf_mDataNum++;
         }
      }

      calcFlag = calcMeanAndSigma(create_Stoc_vOrdersSELL_LOSS_buf_mData, buf_mDataNum, indexMean, indexSigma);
      if(calcFlag == true)      {
         st_vAnalyzedIndexesSELL_Loss.RCI_VAL_MEAN  = NormalizeDouble(indexMean, global_Digits);
         st_vAnalyzedIndexesSELL_Loss.RCI_VAL_SIGMA = NormalizeDouble(indexSigma, global_Digits);
         retFlag = true;         
      }
      else  {
         st_vAnalyzedIndexesSELL_Loss.RCI_VAL_MEAN  = DOUBLE_VALUE_MIN;
         st_vAnalyzedIndexesSELL_Loss.RCI_VAL_SIGMA = DOUBLE_VALUE_MIN;
      }

      // 検証用ファイル出力の終了処理。
//     FileClose(fileHandle1);

      /*
      printf( "[%d]VT 売り　かつ　損失の平均と偏差計算結果" , __LINE__);
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.strategyID = %s", __LINE__, st_vAnalyzedIndexesSELL_Loss.strategyID );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.symbol = %s", __LINE__, st_vAnalyzedIndexesSELL_Loss.symbol);
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.timeframe = %d", __LINE__, st_vAnalyzedIndexesSELL_Loss.timeframe);
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.orderType = %d", __LINE__, st_vAnalyzedIndexesSELL_Loss.orderType);
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.PLFlag = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.PLFlag) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.analyzeTime = %s", __LINE__, TimeToStr(st_vAnalyzedIndexesSELL_Loss.analyzeTime) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MA_GC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MA_GC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MA_GC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MA_GC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MA_DC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MA_DC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MA_DC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MA_DC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MA_Slope5_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MA_Slope5_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MA_Slope5_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MA_Slope5_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MA_Slope25_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MA_Slope25_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MA_Slope25_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MA_Slope25_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MA_Slope75_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MA_Slope75_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MA_Slope75_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MA_Slope75_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.BB_Width_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.BB_Width_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.BB_Width_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.BB_Width_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.IK_TEN_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.IK_TEN_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.IK_TEN_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.IK_TEN_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.IK_CHI_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.IK_CHI_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.IK_CHI_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.IK_CHI_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.IK_LEG_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.IK_LEG_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.IK_LEG_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.IK_LEG_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MACD_GC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MACD_GC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MACD_GC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MACD_GC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MACD_DC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MACD_DC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.MACD_DC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.MACD_DC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.RSI_VAL_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.RSI_VAL_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.RSI_VAL_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.RSI_VAL_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.STOC_VAL_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.STOC_VAL_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.STOC_VAL_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.STOC_VAL_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.STOC_GC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.STOC_GC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.STOC_GC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.STOC_GC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.STOC_DC_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.STOC_DC_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.STOC_DC_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.STOC_DC_SIGMA) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.RCI_VAL_MEAN = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.RCI_VAL_MEAN) );
      printf("[%d]VTst_vAnalyzedIndexesSELL_Loss.RCI_VAL_SIGMA = %s", __LINE__, DoubleToStr(st_vAnalyzedIndexesSELL_Loss.RCI_VAL_SIGMA) );
      */
   }
   else {
      printf("[%d]VT 売り　かつ　損失の仮想取引が%d件のため、平均と偏差計算失敗。", __LINE__, count);
      return false;
   }

//
// 4．売り　かつ　損失の仮想取引のオープン時各指標値は、ここまで。
//
   if(retFlag == false) {  // 計算に成功した項目が1つもない場合は、falseを返す。
      return false;
   }

   return true;
}


// 配列の初期化
// 全項目を初期化するため、処理に時間がかかるので注意。
void initParams()  {

   int i;
   for(i = 0; i < VTRADENUM_MAX; i++) {
      MA_GC_mData[i]      = INT_VALUE_MIN;
      MA_DC_mData[i]      = INT_VALUE_MIN;
      MA_Slope5_mData[i]  = DOUBLE_VALUE_MIN;
      MA_Slope25_mData[i] = DOUBLE_VALUE_MIN;
      MA_Slope75_mData[i] = DOUBLE_VALUE_MIN;
      // 2 ボリンジャーバンドBB
      BB_Width_mData[i]   = DOUBLE_VALUE_MIN;
      // 3 一目均衡表:IK
      IK_TEN_mData[i]     = DOUBLE_VALUE_MIN;
      IK_CHI_mData[i]     = DOUBLE_VALUE_MIN;
      IK_LEG_mData[i]     = DOUBLE_VALUE_MIN;
      // 4 MACD:MACD
      MACD_GC_mData[i]    = INT_VALUE_MIN;
      MACD_DC_mData[i]    = INT_VALUE_MIN;
      //
      // オシレーター分析
      // 1 RSI:RSI
      RSI_VAL_mData[i]    = DOUBLE_VALUE_MIN;
      // 2 ストキャスティクス:STOC
      STOC_VAL_mData[i]   = DOUBLE_VALUE_MIN;
      STOC_GC_mData[i]    = INT_VALUE_MIN;
      STOC_DC_mData[i]    = INT_VALUE_MIN;
      // 4 RCI:RCI
      RCI_VAL_mData[i] = DOUBLE_VALUE_MIN;
   }
   MA_GC_mDataNum = 0;
   MA_DC_mDataNum = 0;
   MA_Slope5_mDataNum = 0;
   MA_Slope25_mDataNum = 0;
   MA_Slope75_mDataNum = 0;
// 2 ボリンジャーバンドBB
   BB_Width_mDataNum = 0;
// 3 一目均衡表:IK
   IK_TEN_mDataNum = 0;
   IK_CHI_mDataNum = 0;
   IK_LEG_mDataNum = 0;
// 4 MACD:MACD
   MACD_GC_mDataNum = 0;
   MACD_DC_mDataNum = 0;
//
// オシレーター分析
// 1 RSI:RSI
   RSI_VAL_mDataNum = 0;
// 2 ストキャスティクス:STOC
   STOC_VAL_mDataNum = 0;
   STOC_GC_mDataNum = 0;
   STOC_DC_mDataNum = 0;
// 4 RCI:RCI
   RCI_VAL_mDataNum = 0;
}

//
// 仮想取引配列st_vOrderIndexes[i]の中から、引数をキーとする項目のインデックスiを返す。
// 配列内に条件を満たすデータが無ければ、-1を返す。
int getIndex_of_st_vOrderIndexes(string   strategyID,
                                 string   symbol,
                                 int      timeframe,
                                 datetime calcTime
                                )
  {
   int i = 0;
   /*
   printf( "[%d]VT 指標検索 ID=%s 通貨=%s 時間軸=%d 時間=%s" , __LINE__ ,
            strategyID,
            symbol,
            timeframe,
            TimeToStr(calcTime));
   */
   for(i = 0; i < VTRADENUM_MAX; i++)     {
      if(st_vOrderIndexes[i].calcTime <= 0) {
         break;
      }
      if(StringLen(st_vOrderIndexes[i].symbol) > 0 && StringLen(symbol) > 0 && StringCompare(st_vOrderIndexes[i].symbol, symbol) == 0
         && st_vOrderIndexes[i].timeframe == timeframe
         && st_vOrderIndexes[i].calcTime == calcTime)  {
         return i;
      }
   }

   return -1;
  }

// 変数で渡した仮想取引の決済損益又は評価損益を求める。
// 入力：m_st_vOrders  = 計算対象の仮想取引
// 入力：criteriaBID   = 評価損益計算に使うのBID
// 入力：criteriaBID   = 評価損益計算に使うのASK
// 出力：outPL         = 決済損益。未決済時は0.0
// 出力：outPLEstimate = 評価損益。決済時は0.0
// 計算失敗時にfalseを返す。それ以外は、trueを返す。
bool calcPL(st_vOrder &m_st_vOrders, double criteriaBID, double criteriaASK, double &outPL, double &outPLEstimate)  {

// 仮想取引m_st_vOrdersの決済損益又は評価損益を計算する。
   double bufPL = 0.0;            // 決済損益
   double bufPLEstimate = 0.0;    // 評価損益
   double bufPriceEstimate = 0.0; // 評価値

// 出力用変数の初期化
   outPL = 0.0;
   outPLEstimate = 0.0;

   if(NormalizeDouble(criteriaBID, global_Digits) < 0.0
      || NormalizeDouble(criteriaASK, global_Digits) < 0.0)     {
      return false;
   }

   if(m_st_vOrders.orderType == OP_BUY)     {
      // 決済価格が入っている場合は、確定損益を返す。
      if(m_st_vOrders.closeTime > 0)  {
         outPL         = NormalizeDouble(m_st_vOrders.closePL, global_Digits);
         outPLEstimate = 0.0;
      }
      // 決済価格が入っていない場合は、評価損益を計算する。
      // ただし、評価損益計算用の引数criteriaBID <= 0.0の時は計算失敗とする。
      else  {
         if(NormalizeDouble(criteriaBID, global_Digits) <= 0.0) {
            return false;
         }
         outPL         = 0.0;
         outPLEstimate = (NormalizeDouble(criteriaBID, global_Digits) - NormalizeDouble(m_st_vOrders.openPrice, global_Digits)) / global_Points;
      }
   }
   else if(m_st_vOrders.orderType == OP_SELL) {
      // 決済価格が入っている場合は、確定損益を返す。
      if(m_st_vOrders.closeTime > 0) {
         outPL = m_st_vOrders.closePL;
         outPLEstimate = 0.0;
      }
      // 決済価格が入っていない場合は、評価損益を計算する。
      // ただし、評価損益計算用の引数criteriaASK <= 0.0の時は計算失敗とする。

      else           {
         if(NormalizeDouble(criteriaASK, global_Digits) <= 0.0) {
            return false;
         }
         outPL         = 0.0;
         outPLEstimate = (-1) * (NormalizeDouble(criteriaASK, global_Digits) - NormalizeDouble(m_st_vOrders.openPrice, global_Digits)) / global_Points;
      }
   }

   return true;
  }

//+-------------------------------------------------------------------------------------+
//| 戦略名と通貨ペアをキー項目として仮想取引を評価し、損益PIPS数を構造体配列に格納する。|
//+-------------------------------------------------------------------------------------+
/*
void create_st_vOrderPLs2(datetime mTargettime  // 計算基準時間。
                         )  {
// 初期化

   int i;
   int j;
   int numvOrder = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      // st_vOrderPLs[i]を初期値にする。
      if(st_vOrderPLs[i].analyzeTime <= 0) {
         break;
      }
      init_st_vOrderPLs(i);
   }
   
   int tfNow = Period();
   int targetShift = iBarShift(global_Symbol, tfNow, mTargettime, false); // 引数mTargetTimeを含む時間軸mSourceTimeframeのシフト

   // 仮想取引の計算前に、可能なら取引を決済する。
   double   mSettlePrice = iClose(global_Symbol, tfNow, targetShift); // 注目しているシフトの終値で決済を試みる。
   datetime mSettleTime  = iTime(global_Symbol, tfNow, targetShift); // 決済時間した時に使う決済時間。
   if(mSettleTime > 0 && mSettlePrice > 0.0
      && TimeCurrent() > lastForceSettlementTime
      ) {  //強制決済用の時間と決済候補価格を取得出来たときだけ、決済処理を実施する。
      v_do_ForcedSettlement(mSettleTime, 
                            mSettlePrice, 
                            global_Symbol,
                            TP_PIPS, 
                            SL_PIPS);
   }

   for(i = 0; i < VTRADENUM_MAX; i++) {
      // 注目した仮想取引st_vOrders[i]の約定日が基準時間st_vOrders[i].openTime以前の意味のある日付の時に、
      // 以降の処理を行う。
      if(st_vOrders[i].openTime <= 0) {
         break;
      }

      if(st_vOrders[i].openTime > 0 && st_vOrders[i].openTime <= mTargettime)  {
         // 戦略名st_vOrders[i].strategyID,　通貨ペアst_vOrders[i].symbolを
         // キーとして、評価結果が損益分析結果st_vOrderPLs[j]に登録済みかどうかを検索する。
         bool flagRegisterd = false;
         int  index = -1;

         for(j = 0; j < VOPTPARAMSNUM_MAX; j++) {
            if(st_vOrderPLs[j].analyzeTime <= 0) {
               // 評価結果が存在していなければ、最初の空き領域を更新対象として、新規追加する。
               index = j;
               break;
            }

            if(StringLen(st_vOrderPLs[j].strategyID) > 0 && StringLen(st_vOrders[i].strategyID) > 0 && StringCompare(st_vOrderPLs[j].strategyID, st_vOrders[i].strategyID) == 0
               && StringLen(st_vOrderPLs[j].symbol) > 0 && StringLen(st_vOrders[i].symbol) > 0 && StringCompare(st_vOrderPLs[j].symbol, st_vOrders[i].symbol) == 0) {
               flagRegisterd = true;
               index = j;
               break;
            }
         }
         if(index < 0) {
            printf("[%d]VT 評価結果の代入先が見つかりません。", __LINE__);
            return ;
         }

         // 評価結果を更新する。
         st_vOrderPLs[index].strategyID  = st_vOrders[i].strategyID;
         st_vOrderPLs[index].symbol      = st_vOrders[i].symbol;
         st_vOrderPLs[index].timeframe   = st_vOrders[i].timeframe;  // 使わないが、値を代入する。
         st_vOrderPLs[index].analyzeTime = mTargettime;

         double bufPL = 0.0; // 実現損益と評価損益の合計
         bool include_estimatePL = false;//　分析時の損益計算に評価損益を含む場合はtrue、実現損益のみでそんえきけいさんをするときはfalseを指定する。
         //
         // 実現損益と評価損益を計算する。
         // 注目している仮想取引st_vOrders[i]が買いの時
         // ※事前にv_do_ForcedSettlementを実行していることから、実現損益と評価損益は計算済み
         // 決済済み損益のみを使用する場合。未決済取引は、引き分け（損益＝０）と判断する。
         if(include_estimatePL == false) {
            if(st_vOrders[i].closeTime > 0 && st_vOrders[i].closeTime <= mTargettime)  {
               bufPL = NormalizeDouble(st_vOrders[i].closePL, global_Digits);
               add_latestTrade_st_vOrders(st_vOrderPLs[index],     // 取引データを追加する損益分析データ
                                          st_vOrders[i].openTime,  // 追加する取引の約定時刻
                                          bufPL                    // 追加する取引の実現損益
                                          );               


            }
         }
         // 未決済約定に関しては評価損益を使用する場合
         else if(include_estimatePL == true) {
            // 決済済みであれば、実現損益を使う
            if(st_vOrders[i].closeTime > 0 && st_vOrders[i].closeTime <= mTargettime)  {
               bufPL = NormalizeDouble(st_vOrders[i].closePL, global_Digits);
               add_latestTrade_st_vOrders(st_vOrderPLs[index],     // 取引データを追加する損益分析データ
                                          st_vOrders[i].openTime,  // 追加する取引の約定時刻
                                          bufPL                    // 追加する取引の実現損益
                                          );               
            }
            // 未決済の場合は評価損益を使う
            else {
               bufPL = NormalizeDouble(st_vOrders[i].estimatePL, global_Digits);
            }
         }


                                    
         
         // 注目している仮想取引の実現損益または評価損益を基に、損益の合計件数及び損益合計を更新する。
         if(NormalizeDouble(bufPL, global_Digits) > 0.0) {
            st_vOrderPLs[index].win    = st_vOrderPLs[index].win + 1;
            st_vOrderPLs[index].Profit = NormalizeDouble(st_vOrderPLs[index].Profit, global_Digits) + NormalizeDouble(bufPL, global_Digits);


         }
         else if(NormalizeDouble(bufPL, global_Digits) < 0.0) {
            st_vOrderPLs[index].lose   = st_vOrderPLs[index].lose + 1;
            st_vOrderPLs[index].Loss   = NormalizeDouble(st_vOrderPLs[index].Loss, global_Digits) + NormalizeDouble(bufPL, global_Digits);
         }
         else {
            st_vOrderPLs[index].even = st_vOrderPLs[index].even + 1;
         }
      }
      else if(st_vOrders[i].openTime <= 0  || st_vOrders[i].openPrice <= 0.0) {
         break;
      }
   }  // for(int i = 0; i < VTRADENUM_MAX; i++) {

   // 最大ドローダウン（PIPS)及びリスクリワード率、プロフィットファクタを計算する。
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(st_vOrderPLs[i].analyzeTime <= 0.0) {
         break;
      }
      if(st_vOrderPLs[i].analyzeTime > 0.0) {
         // 最大ドローダウン（PIPS)の計算
// 休止中         st_vOrderPLs[i].maxDrawdownPIPS = calcMaxDrawDown(st_vOrderPLs[i].strategyID, st_vOrderPLs[i].symbol, st_vOrderPLs[i].timeframe);
         st_vOrderPLs[i].maxDrawdownPIPS = -123456;
         
         // リスクリワード率の計算
         // https://www.ig.com/jp/trading-strategies/risk-reward-ratio-explained-210729
         // 「FXは環境認識が９割」
         // 損切りの平均と利確の平均を表した数値。数字が大きい方が優秀なトレードとされる。
         // 例）損切り平均 10pips、利確平均 20pips の場合、20÷10=2 となる。
         if(st_vOrderPLs[i].lose <= 0) {
            if(st_vOrderPLs[i].win > 0) {
               st_vOrderPLs[i].riskRewardRatio = DOUBLE_VALUE_MAX;
            }
            // 勝ちも負けも０件の時は、リスクリワード率０とする。
            else {
               st_vOrderPLs[i].riskRewardRatio = 0;
            }
         }
         else {
            if(st_vOrderPLs[i].win > 0) {
               double winAVG  = NormalizeDouble(st_vOrderPLs[i].Profit / st_vOrderPLs[i].win,  global_Digits * 2);
               double loseAVG = NormalizeDouble(st_vOrderPLs[i].Loss   / st_vOrderPLs[i].lose, global_Digits * 2);
               st_vOrderPLs[i].riskRewardRatio = MathAbs(NormalizeDouble(winAVG / loseAVG, global_Digits));
            }
            else {
               st_vOrderPLs[i].riskRewardRatio = 0;
            }
         }

         // プロフィットファクタの計算。異常値DOUBLE_VALUE_MIN以外は０以上。
         if(st_vOrderPLs[i].Loss == 0.0 && st_vOrderPLs[i].Profit > 0.0)  {
            st_vOrderPLs[i].ProfitFactor = DOUBLE_VALUE_MAX;
         }
         else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit > 0.0)  {
            st_vOrderPLs[i].ProfitFactor = DoubleToStr(MathAbs(NormalizeDouble(st_vOrderPLs[i].Profit, global_Digits) / NormalizeDouble(st_vOrderPLs[i].Loss, global_Digits)));
            st_vOrderPLs[i].ProfitFactor = NormalizeDouble(st_vOrderPLs[i].ProfitFactor,global_Digits);
         }
         else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit == 0.0)  {
            st_vOrderPLs[i].ProfitFactor = 0;
         }
         // 取引が発生していない場合は、異常値としてDOUBLE_VALUE_MIN
         else  {
            st_vOrderPLs[i].ProfitFactor = DOUBLE_VALUE_MIN;
         }
      }
      else {
         break;
      }
   }


// printf("[%d]VT  時間測定 create_st_vOrderPLs終了 計算基準時間>%s< ", __LINE__, TimeToStr(mTargettime));
   
}
*/

int TEST_COUNTER = 0;
datetime last_create_st_vOrderPLs =  0;// 一度もcreate_st_vOrderPLsを実行していないときは、０。そうでなければ、create_st_vOrderPLsの実行対象になった決済日付の最大値。
void create_st_vOrderPLs(datetime mTargettime  // 計算基準時間。
                         )  {
   // 初期化
   int i;
   int j;
   int numvOrder = 0;
   if(last_create_st_vOrderPLs <= 0) {
      for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
         // st_vOrderPLs[i]を初期値にする。
         if(st_vOrderPLs[i].analyzeTime <= 0) {
            break;
         }
         init_st_vOrderPLs(i);
      }
   }
   
 //  int tfNow = Period();
   // int targetShift = iBarShift(global_Symbol, tfNow, mTargettime, false); // 引数mTargetTimeを含む時間軸mSourceTimeframeのシフト
   int targetShift = iBarShift(global_Symbol, 1, mTargettime,false);
   // 仮想取引の計算前に、可能なら取引を決済する。
   double   mSettlePrice = iClose(global_Symbol, 1, targetShift); // 注目しているシフトの終値で決済を試みる。
   datetime mSettleTime  = iTime(global_Symbol, 1, targetShift); // 決済時間した時に使う決済時間。
//printf( "[%d]VT 基準時刻=%s　決済用価格=%s  決済用価格の時刻=%s" , __LINE__, TimeToStr(mTargettime),
//      DoubleToStr(mSettlePrice, global_Digits),TimeToStr(mSettleTime) );

   if(mSettleTime > 0 && mSettlePrice > 0.0
      && mTargettime > lastForceSettlementTime
      ) {  //強制決済用の時間と決済候補価格を取得出来たときだけ、決済処理を実施する。
//printf( "[%d]VT PLS更新前に強制決済をする　決済用価格=%s  決済用価格の時刻=%s" , __LINE__, DoubleToStr(mSettlePrice, global_Digits),TimeToStr(mSettleTime) );
      
      v_do_ForcedSettlement(mSettleTime, mSettlePrice, global_Symbol, TP_PIPS, SL_PIPS);
   }
   
   datetime maxCloseTime = 0;
int bufNum = get_vOrdersNum();
//printf( "[%d]VT 登録中のトレードは=%d件 ここから" , __LINE__, bufNum );
//output_st_vOrders();
//printf( "[%d]VT 登録中のトレードは=%d件　ここまで" , __LINE__, bufNum );


   for(i = 0; i < VTRADENUM_MAX; i++) {
      // 注目した仮想取引st_vOrders[i]の約定日が基準時間st_vOrders[i].openTime以前の意味のある日付の時に、
      // 以降の処理を行う。
      if(st_vOrders[i].openTime <= 0) {
         break;
      }

//printf( "[%d]VT **%d** 前回のPLｓ更新時刻=%s から 決済用価格の時刻=%sまでをPLsに追加する" , __LINE__, i, TimeToStr(last_create_st_vOrderPLs), TimeToStr(mSettleTime) );
      //前回計算時の決済日時最後から今回の計算基準時間(mTargettime)の間に決済を迎えた取引を分析結果に反映させる。
//      if((st_vOrders[i].openTime > 0 && st_vOrders[i].closeTime <= 0)
//         || (st_vOrders[i].closeTime > last_create_st_vOrderPLs && st_vOrders[i].closeTime <= mSettleTime))  {
      // 決済済み約定のうち、前回計算時の決済日時最後から今回の計算基準時間(mTargettime)の間に決済を迎えた取引を分析結果に反映させる。
      if(st_vOrders[i].closeTime > last_create_st_vOrderPLs && st_vOrders[i].closeTime <= mSettleTime)  {
         // 戦略名st_vOrders[i].strategyID,　通貨ペアst_vOrders[i].symbolを
         // キーとして、評価結果が損益分析結果st_vOrderPLs[j]に登録済みかどうかを検索する。
         bool flagRegisterd = false;
         int  index = -1;
         for(j = 0; j < VOPTPARAMSNUM_MAX; j++) {
            if(st_vOrderPLs[j].analyzeTime <= 0) {
               // 評価結果が存在していなければ、最初の空き領域を更新対象として、新規追加する。
               index = j;
               break;
            }

            if(StringLen(st_vOrderPLs[j].strategyID) > 0 && StringLen(st_vOrders[i].strategyID) > 0 && StringCompare(st_vOrderPLs[j].strategyID, st_vOrders[i].strategyID) == 0
               && StringLen(st_vOrderPLs[j].symbol) > 0 && StringLen(st_vOrders[i].symbol) > 0 && StringCompare(st_vOrderPLs[j].symbol, st_vOrders[i].symbol) == 0) {
               flagRegisterd = true;
               index = j;
               break;
            }
         }
         if(index < 0) {
            printf("[%d]VT 評価結果の代入先が見つかりません。", __LINE__);
         }



         // 評価結果を更新する。
         st_vOrderPLs[index].strategyID  = st_vOrders[i].strategyID;
         st_vOrderPLs[index].symbol      = st_vOrders[i].symbol;
         st_vOrderPLs[index].timeframe   = st_vOrders[i].timeframe;  // 使わないが、値を代入する。
         st_vOrderPLs[index].analyzeTime = mSettleTime;

string tmpBuf = "";
tmpBuf = tmpBuf + "戦略名=" + st_vOrders[i].strategyID + ", ";
tmpBuf = tmpBuf + "通貨ペア=" + st_vOrders[i].symbol + ", ";
tmpBuf = tmpBuf + "チケット=" + IntegerToString(st_vOrders[i].ticket) + ", ";
tmpBuf = tmpBuf + "時間軸=" + IntegerToString(st_vOrders[i].timeframe) + ", ";
tmpBuf = tmpBuf + "売買区分=" + IntegerToString(st_vOrders[i].orderType) + ", ";
tmpBuf = tmpBuf + "約定日=" + TimeToStr(st_vOrders[i].openTime) + ", ";
tmpBuf = tmpBuf + "約定値=" + DoubleToStr(st_vOrders[i].openPrice) + ", ";
tmpBuf = tmpBuf + "決済日=" + TimeToStr(st_vOrders[i].closeTime) + ", ";
tmpBuf = tmpBuf + "決済値=" + DoubleToStr(st_vOrders[i].closePrice) + ", ";
tmpBuf = tmpBuf + "決済損益=" + DoubleToStr(st_vOrders[i].closePL) + ", ";
//printf( "[%d]VT >%s<　のPLに　%sを追加する" , __LINE__, st_vOrderPLs[index].strategyID, tmpBuf);

         double bufPL = 0.0; // 実現損益と評価損益の合計
         //
         // 実現損益と評価損益を計算する。
         // 注目している仮想取引st_vOrders[i]が買いの時
         // ※事前にv_do_ForcedSettlementを実行していることから、実現損益と評価損益は計算済み
         // 決済済み損益のみを使用する。未決済取引は、引き分け（損益＝０）と判断する。
         if(st_vOrders[i].closeTime > 0 && st_vOrders[i].closeTime <= mSettleTime)  {
            bufPL = NormalizeDouble(st_vOrders[i].closePL, global_Digits);
            add_latestTrade_st_vOrders(st_vOrderPLs[index],     // 取引データを追加する損益分析データ
                                       st_vOrders[i].openTime,  // 追加する取引の約定時刻
                                       bufPL                    // 追加する取引の実現損益
                                       );      
            // 最新の決済時刻を取得するため、初回実行時でlast_create_st_vOrderPLs=0の時は決済日付で上書き。それ以外の時は、決済日が大きければ上書き
            if(last_create_st_vOrderPLs == 0 || maxCloseTime <  st_vOrders[i].closeTime) {
               maxCloseTime = st_vOrders[i].closeTime ;
            }
         }
                                    
         
         // 注目している仮想取引の実現損益を基に、損益の合計件数及び損益合計を更新する。決済していなければ、引き分け
         if(NormalizeDouble(bufPL, global_Digits) > 0.0 && st_vOrders[i].closeTime > 0) {
            st_vOrderPLs[index].win    = st_vOrderPLs[index].win + 1;
            st_vOrderPLs[index].Profit = NormalizeDouble(st_vOrderPLs[index].Profit, global_Digits) + NormalizeDouble(bufPL, global_Digits);


         }
         else if(NormalizeDouble(bufPL, global_Digits) < 0.0 && st_vOrders[i].closeTime > 0) {
            st_vOrderPLs[index].lose   = st_vOrderPLs[index].lose + 1;
            st_vOrderPLs[index].Loss   = NormalizeDouble(st_vOrderPLs[index].Loss, global_Digits) + NormalizeDouble(bufPL, global_Digits);
         }
         else {
            st_vOrderPLs[index].even = st_vOrderPLs[index].even + 1;
         }
      }
      else if(st_vOrders[i].openTime <= 0  || st_vOrders[i].openPrice <= 0.0) {
     
         break;
      }
   }  // for(int i = 0; i < VTRADENUM_MAX; i++) {
   // 次回、この関数create_st_vOrderPLsが呼ばれたときは、今回の最大決済日以降を処理対象とするため、last_create_st_vOrderPLsを更新する。
   if(last_create_st_vOrderPLs < maxCloseTime) {
      last_create_st_vOrderPLs = maxCloseTime;
   }

   // 最大ドローダウン（PIPS)及びリスクリワード率、プロフィットファクタを計算する。
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(st_vOrderPLs[i].analyzeTime <= 0.0) {
         break;
      }
      if(st_vOrderPLs[i].analyzeTime > 0.0) {
         // 加重平均を計算する。
         calc_WeighterAVG(st_vOrderPLs[i]);
         
         // 最大ドローダウン（PIPS)の計算
// 休止中         st_vOrderPLs[i].maxDrawdownPIPS = calcMaxDrawDown(st_vOrderPLs[i].strategyID, st_vOrderPLs[i].symbol, st_vOrderPLs[i].timeframe);
         st_vOrderPLs[i].maxDrawdownPIPS = -123456;
         
         // リスクリワード率の計算
         // https://www.ig.com/jp/trading-strategies/risk-reward-ratio-explained-210729
         // 「FXは環境認識が９割」
         // 損切りの平均と利確の平均を表した数値。数字が大きい方が優秀なトレードとされる。
         // 例）損切り平均 10pips、利確平均 20pips の場合、20÷10=2 となる。
         if(st_vOrderPLs[i].lose <= 0) {
            if(st_vOrderPLs[i].win > 0) {
               st_vOrderPLs[i].riskRewardRatio = DOUBLE_VALUE_MAX;
            }
            // 勝ちも負けも０件の時は、リスクリワード率０とする。
            else {
               st_vOrderPLs[i].riskRewardRatio = 0;
            }
         }
         else {
            if(st_vOrderPLs[i].win > 0) {
               double winAVG  = NormalizeDouble(st_vOrderPLs[i].Profit / st_vOrderPLs[i].win,  global_Digits * 2);
               double loseAVG = NormalizeDouble(st_vOrderPLs[i].Loss   / st_vOrderPLs[i].lose, global_Digits * 2);
               st_vOrderPLs[i].riskRewardRatio = MathAbs(NormalizeDouble(winAVG / loseAVG, global_Digits));
            }
            else {
               st_vOrderPLs[i].riskRewardRatio = 0;
            }
         }

         // プロフィットファクタの計算。異常値DOUBLE_VALUE_MIN以外は０以上。
         if(st_vOrderPLs[i].Loss == 0.0 && st_vOrderPLs[i].Profit > 0.0)  {
            st_vOrderPLs[i].ProfitFactor = DOUBLE_VALUE_MAX;
         }
         else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit > 0.0)  {
            st_vOrderPLs[i].ProfitFactor = DoubleToStr(MathAbs(NormalizeDouble(st_vOrderPLs[i].Profit, global_Digits) / NormalizeDouble(st_vOrderPLs[i].Loss, global_Digits)));
            st_vOrderPLs[i].ProfitFactor = NormalizeDouble(st_vOrderPLs[i].ProfitFactor,global_Digits);
         }
         else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit == 0.0)  {
            st_vOrderPLs[i].ProfitFactor = 0;
         }
         // 取引が発生していない場合は、異常値としてDOUBLE_VALUE_MIN
         else  {
            st_vOrderPLs[i].ProfitFactor = DOUBLE_VALUE_MIN;
         }
      }
      else {
         break;
      }
   }


   
}


void calc_WeighterAVG(st_vOrderPL &m_st_vOrderPL) {
   // 損益の加重平均を計算する。
   double tmpWeightedAVG = 0.0;
   int countWeightedAVGNum = 0;
   int ii;

   for(ii = 0; ii < HISTORICAL_NUM; ii++) {
      if(m_st_vOrderPL.latestTrade_time[ii] <= 0) {
         break;
      }
      tmpWeightedAVG = tmpWeightedAVG + NormalizeDouble(m_st_vOrderPL.latestTrade_PL[ii] * (double)(HISTORICAL_NUM - ii), global_Digits);
      countWeightedAVGNum = countWeightedAVGNum + (HISTORICAL_NUM - ii);
   }
   if(countWeightedAVGNum > 0) {
      tmpWeightedAVG = NormalizeDouble(tmpWeightedAVG / countWeightedAVGNum, global_Digits);
   }
   else {
      tmpWeightedAVG = DOUBLE_VALUE_MIN;
   }
   
   m_st_vOrderPL.latestTrade_WeightedAVG = tmpWeightedAVG;

}

void orgcreate_st_vOrderPLs(string mStratName,    // 08WPR, 25PIN, 18CORR
                         datetime mTargettime  // 計算基準時間。
                         )  {
// 初期化

   int i;
   int j;
   int numvOrder = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      // st_vOrderPLs[i]を初期値にする。
      if(st_vOrderPLs[i].analyzeTime <= 0) {
         break;
      }
      init_st_vOrderPLs(i);
   }
   
   int tfNow = Period();
   int targetShift = iBarShift(global_Symbol, tfNow, mTargettime, false); // 引数mTargetTimeを含む時間軸mSourceTimeframeのシフト

   // 仮想取引の計算前に、可能なら取引を決済する。
   double   mSettlePrice = iClose(global_Symbol, tfNow, targetShift); // 注目しているシフトの終値で決済を試みる。
   datetime mSettleTime  = iTime(global_Symbol, tfNow, targetShift); // 決済時間した時に使う決済時間。
   if(mSettleTime > 0 && mSettlePrice > 0.0
      && TimeCurrent() > lastForceSettlementTime
      ) {  //強制決済用の時間と決済候補価格を取得出来たときだけ、決済処理を実施する。
      v_do_ForcedSettlement(mSettleTime, mSettlePrice, global_Symbol, TP_PIPS, SL_PIPS);
   }

   for(i = 0; i < VTRADENUM_MAX; i++) {
      // 注目した仮想取引st_vOrders[i]の約定日が基準時間st_vOrders[i].openTime以前の意味のある日付の時に、
      // 以降の処理を行う。
      if(st_vOrders[i].openTime <= 0) {
         break;
      }
      if(StringFind(st_vOrders[i].strategyID, mStratName, 0) < 0) {
         // st_vOrders[i].strategyIDが、mStratName（08WPR）を含んでいなければ、計算対象外とする。
         continue;
      }

      if(st_vOrders[i].openTime > 0 && st_vOrders[i].openTime <= mTargettime)  {
         // 戦略名st_vOrders[i].strategyID,　通貨ペアst_vOrders[i].symbolを
         // キーとして、評価結果が損益分析結果st_vOrderPLs[j]に登録済みかどうかを検索する。
         bool flagRegisterd = false;
         int  index = -1;

         for(j = 0; j < VOPTPARAMSNUM_MAX; j++) {
            if(st_vOrderPLs[j].analyzeTime <= 0) {
               // 評価結果が存在していなければ、最初の空き領域を更新対象として、新規追加する。
               index = j;
               break;
            }

            if(StringLen(st_vOrderPLs[j].strategyID) > 0 && StringLen(st_vOrders[i].strategyID) > 0 && StringCompare(st_vOrderPLs[j].strategyID, st_vOrders[i].strategyID) == 0
               && StringLen(st_vOrderPLs[j].symbol) > 0 && StringLen(st_vOrders[i].symbol) > 0 && StringCompare(st_vOrderPLs[j].symbol, st_vOrders[i].symbol) == 0) {
               flagRegisterd = true;
               index = j;
               break;
            }
         }
         if(index < 0) {
            printf("[%d]VT 評価結果の代入先が見つかりません。", __LINE__);
            return ;
         }

         // 評価結果を更新する。
         st_vOrderPLs[index].strategyID  = st_vOrders[i].strategyID;
         st_vOrderPLs[index].symbol      = st_vOrders[i].symbol;
         st_vOrderPLs[index].timeframe   = st_vOrders[i].timeframe;  // 使わないが、値を代入する。
         st_vOrderPLs[index].analyzeTime = mTargettime;

         double bufPL = 0.0; // 実現損益と評価損益の合計
         bool include_estimatePL = false;
         //
         // 実現損益と評価損益を計算する。
         // 注目している仮想取引st_vOrders[i]が買いの時
         // ※事前にv_do_ForcedSettlementを実行していることから、実演曽根貴登評価損益は計算済み
         // 決済済み損益のみを使用する場合。未決済取引は、引き分け（損益＝０）と判断する。
         if(include_estimatePL == false) {
            if(st_vOrders[i].closeTime > 0 && st_vOrders[i].closeTime <= mTargettime)  {
               bufPL = NormalizeDouble(st_vOrders[i].closePL, global_Digits);
            }
         }
         // 未決済約定に関しては評価損益を使用する場合
         else if(include_estimatePL == true) {
            // 決済済みであれば、実現損益を使う
            if(st_vOrders[i].closeTime > 0 && st_vOrders[i].closeTime <= mTargettime)  {
               bufPL = NormalizeDouble(st_vOrders[i].closePL, global_Digits);
               
               // st_vOrders[i].openTimeとbufPLをst_vOrderPL[i].latestTrade_time[], latestTrade_time[]に追加する。
               add_latestTrade_st_vOrders(st_vOrderPLs[index],     // 取引データを追加する損益分析データ
                                          st_vOrders[i].openTime,  // 追加する取引の約定時刻
                                          bufPL                    // 追加する取引の損益
                                    );               
            }
            // 未決済の場合は評価損益を使う
            else {
               bufPL = NormalizeDouble(st_vOrders[i].estimatePL, global_Digits);
            }
         }


                                    
         
         // 注目している仮想取引の実現損益または評価損益を基に、損益の合計件数及び損益合計を更新する。
         if(NormalizeDouble(bufPL, global_Digits) > 0.0) {
            st_vOrderPLs[index].win    = st_vOrderPLs[index].win + 1;
            st_vOrderPLs[index].Profit = NormalizeDouble(st_vOrderPLs[index].Profit, global_Digits) + NormalizeDouble(bufPL, global_Digits);


         }
         else if(NormalizeDouble(bufPL, global_Digits) < 0.0) {
            st_vOrderPLs[index].lose   = st_vOrderPLs[index].lose + 1;
            st_vOrderPLs[index].Loss   = NormalizeDouble(st_vOrderPLs[index].Loss, global_Digits) + NormalizeDouble(bufPL, global_Digits);
         }
         else {
            st_vOrderPLs[index].even = st_vOrderPLs[index].even + 1;
         }
      }
      else if(st_vOrders[i].openTime <= 0  || st_vOrders[i].openPrice <= 0.0) {
         break;
      }
   }  // for(int i = 0; i < VTRADENUM_MAX; i++) {


   // 最大ドローダウン（PIPS)及びリスクリワード率、プロフィットファクタを計算する。
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(st_vOrderPLs[i].analyzeTime <= 0.0) {
         break;
      }
      if(st_vOrderPLs[i].analyzeTime > 0.0) {
         // 最大ドローダウン（PIPS)の計算
// 休止中         st_vOrderPLs[i].maxDrawdownPIPS = calcMaxDrawDown(st_vOrderPLs[i].strategyID, st_vOrderPLs[i].symbol, st_vOrderPLs[i].timeframe);
         st_vOrderPLs[i].maxDrawdownPIPS = -123456;
         
         // リスクリワード率の計算
         // https://www.ig.com/jp/trading-strategies/risk-reward-ratio-explained-210729
         // 「FXは環境認識が９割」
         // 損切りの平均と利確の平均を表した数値。数字が大きい方が優秀なトレードとされる。
         // 例）損切り平均 10pips、利確平均 20pips の場合、20÷10=2 となる。
         if(st_vOrderPLs[i].lose <= 0) {
            if(st_vOrderPLs[i].win > 0) {
               st_vOrderPLs[i].riskRewardRatio = DOUBLE_VALUE_MAX;
            }
            // 勝ちも負けも０件の時は、リスクリワード率０とする。
            else {
               st_vOrderPLs[i].riskRewardRatio = 0;
            }
         }
         else {
            if(st_vOrderPLs[i].win > 0) {
               double winAVG  = NormalizeDouble(st_vOrderPLs[i].Profit / st_vOrderPLs[i].win,  global_Digits * 2);
               double loseAVG = NormalizeDouble(st_vOrderPLs[i].Loss   / st_vOrderPLs[i].lose, global_Digits * 2);
               st_vOrderPLs[i].riskRewardRatio = MathAbs(NormalizeDouble(winAVG / loseAVG, global_Digits));
            }
            else {
               st_vOrderPLs[i].riskRewardRatio = 0;
            }
         }

         // プロフィットファクタの計算。異常値DOUBLE_VALUE_MIN以外は０以上。
         if(st_vOrderPLs[i].Loss == 0.0 && st_vOrderPLs[i].Profit > 0.0)  {
            st_vOrderPLs[i].ProfitFactor = DOUBLE_VALUE_MAX;
         }
         else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit > 0.0)  {
            st_vOrderPLs[i].ProfitFactor = DoubleToStr(MathAbs(NormalizeDouble(st_vOrderPLs[i].Profit, global_Digits) / NormalizeDouble(st_vOrderPLs[i].Loss, global_Digits)));
            st_vOrderPLs[i].ProfitFactor = NormalizeDouble(st_vOrderPLs[i].ProfitFactor,global_Digits);
         }
         else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit == 0.0)  {
            st_vOrderPLs[i].ProfitFactor = 0;
         }
         // 取引が発生していない場合は、異常値としてDOUBLE_VALUE_MIN
         else  {
            st_vOrderPLs[i].ProfitFactor = DOUBLE_VALUE_MIN;
         }
      }
      else {
         break;
      }
   }
   
}


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string getVirtualTradeResults()  {
   string ret = "";

   // 仮想取引の損益分析をする。
   create_st_vOrderPLs(TimeCurrent());

   // 仮想取引データをstringに変換する。
   for(int i = 0; i < VOPTPARAMSNUM_MAX; i++)  {
      if(st_vOrderPLs[i].analyzeTime <= 0)  {
         break;
      }
      if(st_vOrderPLs[i].analyzeTime > 0)  {
         // プロフィットファクターのコメント設定
         string bufPF = "";
         if(st_vOrderPLs[i].Loss == 0.0 && st_vOrderPLs[i].Profit > 0.0)  {
            bufPF = "全勝中";
         }
         else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit > 0.0)  {
            bufPF = DoubleToStr(MathAbs(NormalizeDouble(st_vOrderPLs[i].Profit, global_Digits) / NormalizeDouble(st_vOrderPLs[i].Loss, global_Digits)));
         }
         else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit == 0.0)  {
            bufPF = "全て敗け";
         }
         else  {
            bufPF = "**";
         }

         // リスクリワード率の計算
         string bufRRRatio = "";
         double bufRatio = 0.0;
         // 以下の2行は、st_vOrderPLs[i].riskRewardRatioをcreate_st_vOrderPLsで計算していることから削除。
         // bufRatio = get_RiskRewardRatio(st_vOrderPLs[i].strategyID, st_vOrderPLs[i].symbol);
         // st_vOrderPLs[i].riskRewardRatio = NormalizeDouble(bufRatio, global_Digits);
         bufRatio = st_vOrderPLs[i].riskRewardRatio;
         if(bufRatio >= RISKREWARD_PERCENT)  {
            bufRRRatio = DoubleToStr(bufRatio, global_Digits) + "%";
         }
         else  {
            bufRRRatio = DoubleToStr(bufRatio, global_Digits) + "%　←　境界値" + DoubleToStr(RISKREWARD_PERCENT, 2) + "%未満";
         }

         ret = ret + st_vOrderPLs[i].strategyID + " "
               + st_vOrderPLs[i].symbol + " "
               + "時間軸=" + IntegerToString(st_vOrderPLs[i].timeframe) + " "
               + IntegerToString(st_vOrderPLs[i].win) + "勝"
               + IntegerToString(st_vOrderPLs[i].lose) + "敗"
               + IntegerToString(st_vOrderPLs[i].even) + "分"
               + "利益=" + DoubleToStr(st_vOrderPLs[i].Profit, global_Digits) + " "
               + "損失=" + DoubleToStr(st_vOrderPLs[i].Loss, global_Digits)  + " "
               + "PF=" + bufPF + " "
               + "リスクリワード率" + bufRRRatio + " \n";
      }
   }

   return ret;
}



// 戦略名＋通貨ペア＋時間軸をキーとして、最大ドローダウン（PIPS）を返す。
// 計算に成功した場合は、負の数を返す。
// 計算に失敗した場合は、DOUBLE_VALUE_MAXを返す。
// ※この関数は、create_st_vOrderPLs()内でのみ実行すること。
double calcDD[VTRADENUM_MAX][3]; // 512KBを超える配列を関数内に作れないため、グローバル変数とした。
double calcMaxDrawDown(string strStratName, string strSymbol, int intTF) {
// 必要なデータがそろっていなければ、エラー値を返す。
   if(global_Points <= 0)  {
      return DOUBLE_VALUE_MAX;
   }

// ドローダウンを計算する変数を定義
   

// 初期化
   int i;
   int j;
   for(i = 0; i < VTRADENUM_MAX; i++)  {
      calcDD[i][0] = 0.0;
      calcDD[i][1] = 0.0;
      calcDD[i][2] = 0.0;
   }

// 出発点に初期投資額を設定
   calcDD[0][1] = 0.0;
   int calcDDcounter = 0;
   
   for(i = 0; i < VTRADENUM_MAX; i++)  {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }
      if(StringLen(st_vOrders[i].strategyID) > 0 && StringLen(strStratName) > 0 && StringCompare(st_vOrders[i].strategyID, strStratName, true) == 0
         && StringLen(st_vOrders[i].symbol) > 0 && StringLen(strSymbol) > 0 && StringCompare(st_vOrders[i].symbol, strSymbol, true) == 0
         && st_vOrders[i].timeframe == intTF)  {
         calcDDcounter++;

         // 収支（損益）を計算する。決済前の場合は、ASK又はBIDを使って評価損益を計算する。
         double bufPL = 0.0;
         if(st_vOrders[i].orderType == OP_BUY)  {
            if(st_vOrders[i].closeTime > 0)  {
               bufPL = (NormalizeDouble(st_vOrders[i].closePrice, global_Digits) - NormalizeDouble(st_vOrders[i].openPrice, global_Digits)) / global_Points;
            }
            else  {
               bufPL = (NormalizeDouble(MarketInfo(global_Symbol,MODE_BID), global_Digits) - NormalizeDouble(st_vOrders[i].openPrice, global_Digits)) / global_Points;
            }
         }
         else if(st_vOrders[i].orderType == OP_SELL)  {
            if(st_vOrders[i].closeTime > 0)  {
               bufPL = (-1) * (NormalizeDouble(st_vOrders[i].closePrice, global_Digits) - NormalizeDouble(st_vOrders[i].openPrice, global_Digits)) / global_Points;
            }
            else {
               bufPL = (-1)*(NormalizeDouble(MarketInfo(global_Symbol,MODE_ASK), global_Digits) - NormalizeDouble(st_vOrders[i].openPrice, global_Digits)) / global_Points;
            }
         }

         // calcDD[No][0] = 収支
         calcDD[calcDDcounter][0] = bufPL;

         // calcDD[No][1] = 資産推移 = calcDD[No - 1][1] + calcDD[No][0] = 前回の資産推移(B2)＋今回の収支(A3)
         calcDD[calcDDcounter][1] = NormalizeDouble(calcDD[calcDDcounter - 1][1], global_Digits) + NormalizeDouble(calcDD[calcDDcounter][0], global_Digits);

         // calcDD[No][2] = ドローダウン = (Max(calcDD[0][1]～calcDD[No][1]) - calcDD[No][1]) * (-1)
         //               = （初回から今回までの資産推移最大値 - 今回の資産推移）×（－１）
         double bufMax = DOUBLE_VALUE_MIN;
         for(j = 0; j <= calcDDcounter; j++)  {
            if(bufMax < calcDD[j][1])  {
               bufMax = calcDD[j][1];
            }
         }
         if(bufMax > DOUBLE_VALUE_MIN)  {
            calcDD[calcDDcounter][2] = (NormalizeDouble(bufMax, global_Digits) - NormalizeDouble(calcDD[calcDDcounter][1], global_Digits)) * (-1);
         }
         else  {
            calcDD[calcDDcounter][2] = 0.0;
         }
      }
   }  //for(i = 0; i < VTRADENUM_MAX; i++) {

   // ドローダウンの最小値を求める
   double bufMin = DOUBLE_VALUE_MAX;
   for(j = 0; j <= calcDDcounter; j++)  {
      if(bufMin > calcDD[j][2])  {
         bufMin = calcDD[j][2];
      }
   }

   return bufMin;
}


// リスクリワード：利確の合計平均：損切りの合計平均　例）週あたりのリスクリワード
// リスクリターン：その取引の利確：その取引の損切り
// リスクリワード率(0.0%～100.0%)を取得する。
// リスクリワード率は、利益PIPS / 最大ドローダウンPIPS　× 100で求める。
// ただし、利益は発生しているものの、最大ドローダウンPIPSが発生していない場合は、DOUBLE_VALUE_MAX(999.999)%とする。
// 取得に失敗した場合は、DOUBLE_VALUE_MINを返す。
double get_RiskRewardRatio(string strStratName, // リスクリワードの計算対象とする仮想取引の戦略名
                           string strSymbol     // リスクリワードの計算対象とする仮想取引の通貨ペア
//  仮想取引発注時の時間軸は使わない。                         int    intTF         // リスクリワードの計算対象とする仮想取引の時間軸
                          ) {
   double bufRatio = 0.0;
   // 必要なデータがそろっていなければ、エラー値を返す。
   if(global_Points <= 0)  {
      return DOUBLE_VALUE_MIN;
   }

   int i = 0;
   int vOrderPLsNum = 0; // 計算対象とした仮想取引の損益集計結果が無ければ、関数が負の値DOUBLE_VALUE_MINを返す。
   for(i = 0; i < VTRADENUM_MAX; i++)  {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }
      if(StringLen(st_vOrderPLs[i].strategyID) > 0 && StringLen(strStratName) > 0 && StringCompare(st_vOrderPLs[i].strategyID, strStratName, true) == 0
         && StringLen(st_vOrderPLs[i].symbol) > 0 && StringLen(strSymbol) > 0 && StringCompare(st_vOrderPLs[i].symbol, strSymbol, true) == 0) {
         vOrderPLsNum++;  // 損益集計結果の個数

         if(st_vOrderPLs[i].maxDrawdownPIPS < 0.0)  {
            // 最大ドローダウンmaxDrawdownPIPSは、原則として負のため、リスクリワード率計算時に-1をかけることでリスクリワード率を原則として正とする。。
            bufRatio = NormalizeDouble(st_vOrderPLs[i].Profit, global_Digits) / NormalizeDouble(st_vOrderPLs[i].maxDrawdownPIPS, global_Digits) * 100 * (-1);
            //printf( "[%d]VT 戦略%sのリスクリワード率%s＝%s / %s。" , __LINE__, strStratName, DoubleToStr(bufRatio, global_Digits),
            //                   DoubleToStr(st_vOrderPLs[i].Profit, global_Digits),
            //                   DoubleToStr(st_vOrderPLs[i].maxDrawdownPIPS, global_Digits) );
         }
         else if(st_vOrderPLs[i].maxDrawdownPIPS > 0.0) {
            // ドローダウンが正という想定外のため、負の値を返す。
            bufRatio = DOUBLE_VALUE_MIN;
         }
         else if(st_vOrderPLs[i].maxDrawdownPIPS == 0.0 
                 && st_vOrderPLs[i].Profit > 0.0) {
            // 全勝でドローダウンが発生していない場合は、リスクリワード率をDOUBLE_VALUE_MAX%とする。
            bufRatio = DOUBLE_VALUE_MAX;
         }
         else  {
            bufRatio = 0.0;
         }

         break;  // 引数で検索された損益集計結果を使ってリスクリワードを計算できたので、ループを抜ける
      }
   }

   // 計算対象とした損益集計結果が無ければ、負の値を返す。
   if(vOrderPLsNum == 0) {    
      bufRatio = DOUBLE_VALUE_MIN;   
   }

   return bufRatio;
}


// プロフィットファクターPFを取得する。
// PFは、利益PIPS / 損失の絶対値。0より大。
// 全勝の時はDOUBLE_VALUE_MAXとし、全敗の時は、DOUBLE_VALUE_MINとする。
double get_ProfitFactor(string strStratName, // PFを取得する仮想取引の戦略名
                        string strSymbol     // PFを取得する仮想取引の通貨ペア
                          ) {

   int i = 0;
   double bufPF = DOUBLE_VALUE_MIN;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++)  {
      if(st_vOrderPLs[i].analyzeTime <= 0) {
         break;
      }

      if(StringLen(st_vOrderPLs[i].strategyID) > 0 && StringLen(strStratName) > 0 && StringCompare(st_vOrderPLs[i].strategyID, strStratName, true) == 0
         && StringLen(st_vOrderPLs[i].symbol) > 0 && StringLen(strSymbol) > 0 && StringCompare(st_vOrderPLs[i].symbol, strSymbol, true) == 0) {
         if(st_vOrderPLs[i].Loss == 0.0 && st_vOrderPLs[i].Profit > 0.0)  {
            // 全勝
            bufPF = DOUBLE_VALUE_MAX;
         }
         else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit > 0.0)  {
            bufPF = DoubleToStr(MathAbs(NormalizeDouble(st_vOrderPLs[i].Profit, global_Digits) / NormalizeDouble(st_vOrderPLs[i].Loss, global_Digits)));
         }
         else if(st_vOrderPLs[i].Loss < 0.0 && st_vOrderPLs[i].Profit == 0.0)  {
            // 全敗
            bufPF = DOUBLE_VALUE_MIN;
         }
         else  {
            bufPF = DOUBLE_VALUE_MIN;
         }
         return bufPF;
         
      }
   }

   return DOUBLE_VALUE_MIN;
}

//
// 引数で渡す開始時間を使った仮想取引（売り、買い両方）をする。
//
// 失敗が発生すれば、INT_VALUE_MIN(= -9999)を返す。それ以外は、0以上の登録件数を返す。
int v_mOrderSend(datetime mOpenTime, 
                 string mStrategyID,
                 string mSymbol,
                 int mTimeFrame,
                 int mJudgeMethod, 
                 double positiveSigma, 
                 double negativeSigma)  {
   int i = 0;
   st_vOrderIndex curr_st_vOrderIndex;

   int retCount = 0;
   int tickNo = -1;
   double mOpenprice = 0.0;

   int calcShift;

   // 仮想取引の発注判断前に、引数mOpenTimeが約定時間の仮想取引は、クリアする。
   delete_vOrder(mOpenTime);

   // 引数mOpenTimeが約定時間の仮想取引を試みる。
   // 【発注ロジック】
   //    現時点(引数mOpenTime)の指標と現時点(引数mOpenTime)以前の仮想取引結果から取りうる範囲を計算し、
   //    現時点(i)の全指標が、過去の仮想取引から計算する指標が取りうる範囲内であれば、取引する。

   // mOpenTime=st_vOrders[].openTimeを満たす仮想取引が存在すれば、以降の処理はしない。
   if(exist_vOrder(mOpenTime) == false)  {
      // 仮想取引の発注
      bool v_calcIndexes = false;

      //
      // 現時点(引数mOpenTime)以前の仮想取引が存在しない場合は、無条件に発注する。
      // ＝過去の仮想取引を使った指標計算が、仮想取引未登録のためできないケース。
      int count;
      count = getNumber_of_vOrders(mStrategyID,
                                   global_Symbol,                  // 入力：EURUSD-CDなど
                                   mTimeFrame,                     // 入力：時間軸。0は不可。PERIOD_M1～PERIOD_MN1
                                   0,                      // 入力：仮想取引の約定時間がこの値以降。
                                   mOpenTime - 1                      // 入力：仮想取引の約定時間がこの値以前。
                                  ) ;
      if(count <= 0)  {
         calcShift  = iBarShift(global_Symbol, mTimeFrame, mOpenTime, false);
         mOpenprice = iClose(global_Symbol,mTimeFrame,calcShift);
         tickNo = v_mOrderSend4(mOpenTime, global_Symbol, OP_BUY,  LOTS, mOpenprice, SLIPPAGE, 0.0, 0.0, mStrategyID, 0, 0, LINE_COLOR_LONG);
         if(tickNo > 0)  {
            retCount++;
         }
   

         tickNo = v_mOrderSend4(mOpenTime, global_Symbol, OP_SELL, LOTS, mOpenprice, SLIPPAGE, 0.0, 0.0, mStrategyID, 0, 0, LINE_COLOR_SHORT);

         
         if(tickNo > 0)  {
            retCount++;
         }
      }
      // 現時点(シフトi)以前の仮想取引が存在する場合は、各種指標データを計算し、条件があえば発注する。。
      else {
         //printf( "[%d]VT 約定時間%sの仮想取引を検討中。" , __LINE__, TimeToStr(mOpenTime));

         // 現時点(シフトi)の仮想取引は、一旦削除する。
         //delete_vOrder(mOpenTime);
         // 現時点の指標をcurr_st_vOrderIndexに入れる。
         v_calcIndexes = v_calcIndexes(mStrategyID, mSymbol, mTimeFrame, mOpenTime, curr_st_vOrderIndex);


         // 現時点(mOpenTime)の指標計算に失敗した場合は、無条件に発注する。→発注不可
         if(v_calcIndexes == false)  {
            printf("[%d]VT 現時点の指標計算に失敗。約定時間%sの仮想取引を発注しない。", __LINE__, TimeToStr(mOpenTime));
         }      // 現時点の指標計算に失敗した時、ここまで。
         else  { // 現時点の指標計算に成功した時、以下を行う。
            // 現時点(mOpenTime)以前の仮想取引から買い＆利益、買い＆損失、売り＆利益、売り＆損失それぞれの
            // 指標の平均と偏差を計算し、
            // グローバル変数st_vAnalyzedIndexesBUY_Profit,st_vAnalyzedIndexesBUY_Loss,
            // st_vAnalyzedIndexesSELL_Profit,st_vAnalyzedIndexesSELL_Loss
            // に代入する。
            // 引数渡しする開始時間を0、終了時間をmOpenTime - 1とし、
            // 終了時間までの仮想取引を基に、指標の平均と偏差を計算する。
            bool flagRange[4];
            bool flagRangeOfBP = create_Stoc_vOrdersBUY_PROFIT(mStrategyID, mSymbol, mTimeFrame, mOpenTime, 0, mOpenTime - 1);
            
            flagRange[0] = flagRangeOfBP;
            bool flagRangeOfBL = create_Stoc_vOrdersBUY_LOSS(mStrategyID, mSymbol, mTimeFrame, mOpenTime, 0, mOpenTime - 1);
            flagRange[1] = flagRangeOfBL;
            bool flagRangeOfSP = create_Stoc_vOrdersSELL_PROFIT(mStrategyID, mSymbol, mTimeFrame, mOpenTime, 0, mOpenTime - 1);
            flagRange[2] = flagRangeOfSP;

            bool flagRangeOfSL = create_Stoc_vOrdersSELL_LOSS(mStrategyID, mSymbol, mTimeFrame, mOpenTime, 0, mOpenTime - 1);
            flagRange[3] = flagRangeOfSL;

            // 計算に失敗(BP, BL, SP, SLが全てfalse)した場合は、発注しない
            if(flagRangeOfBP    == false
               && flagRangeOfBL == false
               && flagRangeOfSP == false
               && flagRangeOfSL == false) {
               printf("[%d]VT 指標の平均と偏差。約定時間%sの仮想取引を発注しない。", __LINE__, TimeToStr(mOpenTime));
            }

            else {
            // 平均と偏差の計算に成功した場合は、
            // 現時点(i)の全指標が、過去の仮想取引から計算する指標が取りうる範囲内かどうかの判断をする。

            if(judgeTradable(OP_BUY, flagRange, mJudgeMethod, curr_st_vOrderIndex, positiveSigma, negativeSigma) == true) {
               calcShift  = iBarShift(global_Symbol, mTimeFrame, mOpenTime, false);
               mOpenprice = iClose(global_Symbol,mTimeFrame,calcShift);
               tickNo = v_mOrderSend4(mOpenTime, global_Symbol, OP_BUY,  LOTS, mOpenprice, SLIPPAGE, 0.0, 0.0, mStrategyID, 0, 0, LINE_COLOR_LONG);
               
               if(tickNo > 0) {
                  printf("[%d]VT 現時点(i)%sの条件を満たし仮想取引（買い）を追加。", __LINE__, TimeToStr(mOpenTime));
                  retCount++;
               }
            }
            else {
               printf("[%d]VT 現時点(i)%sの条件を満たさないため仮想取引（買い）断念。", __LINE__, TimeToStr(mOpenTime));

            }

            if(judgeTradable(OP_SELL, flagRange, mJudgeMethod, curr_st_vOrderIndex, positiveSigma, negativeSigma) == true)  {
              
               calcShift  = iBarShift(global_Symbol, mTimeFrame, mOpenTime, false);
               mOpenprice = iClose(global_Symbol,mTimeFrame,calcShift);
               tickNo = v_mOrderSend4(mOpenTime, global_Symbol, OP_SELL, LOTS, mOpenprice, SLIPPAGE, 0.0, 0.0, mStrategyID, 0, 0, LINE_COLOR_SHORT);
               
               if(tickNo > 0) {
                  retCount++;
                  printf("[%d]VT 現時点(i)%sの条件を満たし仮想取引（売り）を追加。", __LINE__, TimeToStr(mOpenTime));
               }
            }  // 判断結果がtrueであれば、判断した取引（買い（売り））を発注する。
            else  {
               printf("[%d]VT 現時点(i)%sの条件を満たさないため仮想取引（売り）断念。", __LINE__, TimeToStr(mOpenTime));

            }
         }     // else {  // 計算に成功(flag_getStoc_vOrders==true)した場合
      }  // 現時点(i)の指標計算に成功した時、以下を行う。
   }     // else ←　仮想取引が0件より大。
}        // if(exist_vOrder(mOpenTime) == false) 　←　まだ、当該時間で発注していない。


return retCount;
}


//
// 現在の時間軸で、引数で渡すシフトの間、シフトの開始時間を使った仮想取引（売り、買い両方）をする。
//
// mShiftFrom＝取引発注をする直近のシフト数
// mShiftTo  ＝取引発注をする最古のシフト数
// 各シフトで売りと買いの両方を発注するため、実行可能なのは、VTRADENUM_MAX > (mShiftTo - mShiftFrom) * 2を満たす時のみ。
// 失敗が発生すれば、INT_VALUE_MIN(= -9999)を返す。それ以外は、0以上の登録件数を返す。
int v_mOrderSendBatch(string mStrategyID,
                      string mSymbol,
                      int mTimeFrame,
                      int mShiftFrom, int mShiftTo, int mJudgeMethod, double positiveSigma, double negativeSigma)  {
   int i = 0;
   st_vOrderIndex curr_st_vOrderIndex;

   if(mShiftFrom > mShiftTo)  {
      return INT_VALUE_MIN;
   }
   if(mShiftFrom < 0)  {
      return INT_VALUE_MIN;
   }
   if(mShiftTo < 0)  {
      return INT_VALUE_MIN;
   }
   // 各シフトで売りと買いの両方を発注するため、個数を制限する
   if(VTRADENUM_MAX <= (mShiftTo - mShiftFrom) * 2)  {
      return INT_VALUE_MIN;
   }



   int retCount = 0;
   int tickNo = -1;
   double mOpenprice = 0.0;
   datetime mOpenTime = 0;

   // 仮想取引の発注開始mShiftFromシフトから前の時間を約定時間とする仮想取引を試みる。
   // 【発注ロジック】
   //    仮想取引の発注時間iの各々で、現時点(シフトi)の指標とi以前の仮想取引結果から計算した
   //    現時点(シフトi)の指標及び過去(シフトi～i + )の仮想取引から指標が取りうる範囲を計算し、
   //    現時点(i)の全指標が、過去の仮想取引から計算する指標が取りうる範囲内であれば、取引する。
   for(i = mShiftFrom; i <= mShiftTo; i++)  {
      mOpenTime = iTime(global_Symbol,0,i);

      // 仮想取引の発注
      // 現時点(シフトi)の指標及び過去(シフトi～i + )の仮想取引から指標が取りうる範囲を計算し、
      // 現時点(i)の全指標が、過去の仮想取引から計算する指標が取りうる範囲内であれば、取引する。
      bool v_calcIndexes = false;

      //
      // 現時点(シフトi)で仮想取引が存在しない場合は、無条件に発注する。＝過去の仮想取引を使った指標計算が、仮想取引未登録のためできないケース。
      int count;
      count = getNumber_of_vOrders(mStrategyID,
                                   global_Symbol,   // 入力：EURUSD-CDなど
                                   mTimeFrame,      // 入力：時間軸。0は不可。PERIOD_M1～PERIOD_MN1
                                   -1,              // 入力：仮想取引の約定時間がこの値以降。
                                   mOpenTime        // 入力：仮想取引の約定時間がこの値以前。現時点(i)より1つ以上過去を探す。
                                  ) ;
      if(count <= 0)   {
         /*
         printf( "[%d]VT 現時点(i)%s以前の仮想取引がない=%d件。" , __LINE__,
                    TimeToStr(mOpenTime),
                    count);
         */
         mOpenprice = iClose(global_Symbol,0,i);
         tickNo = v_mOrderSend4(mOpenTime, global_Symbol, OP_BUY,  LOTS, mOpenprice, SLIPPAGE, 0.0, 0.0, mStrategyID, 0, 0, LINE_COLOR_LONG);
         if(tickNo > 0)  {
            retCount++;
         }

         tickNo = v_mOrderSend4(mOpenTime, global_Symbol, OP_SELL, LOTS, mOpenprice, SLIPPAGE, 0.0, 0.0, mStrategyID, 0, 0, LINE_COLOR_SHORT);
         if(tickNo > 0)  {
            retCount++;
         }
      }
      // 現時点(シフトi)以前の仮想取引が存在する場合は、各種指標データを計算し、条件があえば発注する。。
      else  {
         // 現時点(シフトi)の仮想取引は、一旦削除する。
         delete_vOrder(mOpenTime);

         // 現時点の指標をcurr_st_vOrderIndexに入れる。
         v_calcIndexes = v_calcIndexes(mStrategyID, mSymbol, mTimeFrame, mOpenTime, curr_st_vOrderIndex);

         // 現時点(i)の指標計算に失敗した場合は、発注不可。
         if(v_calcIndexes == false)   {
            printf("[%d]VT 現時点(i)の指標計算に失敗。約定時間%sの仮想取引を発注しない。", __LINE__, TimeToStr(mOpenTime));
         }      // 現時点(i)の指標計算に失敗した時、ここまで。
         else  { // 現時点(i)の指標計算に成功した時、以下を行う。
            bool flag_getStoc_vOrders = false;
            // 現時点(i)以前の仮想取引から買い＆利益、買い＆損失、売り＆利益、売り＆損失それぞれの
            // 指標の平均と偏差を計算し、
            // グローバル変数st_vAnalyzedIndexesBUY_Profit,st_vAnalyzedIndexesBUY_Loss,
            // st_vAnalyzedIndexesSELL_Profit,st_vAnalyzedIndexesSELL_Loss
            // に代入する。
            // 関数getStoc_vOrdersで引数渡しする開始時間を0、終了時間をiTime(mSymbol,mTimeFrame,0)とし、
            // この処理を実行した時点までの仮想取引を基に、指標の平均と偏差を計算する。

            // 最古の仮想取引（約定日時=0)から現時点(i)のシフト1つ過去（約定日時=i+1)の仮想取引を対象に平均と偏差を計算する。
            flag_getStoc_vOrders = create_st_vAnalyzedIndex(mStrategyID,
                                                   mSymbol,
                                                   mTimeFrame,
                                                   mOpenTime,            // 計算基準時間
                                                   0,                    // 指標の平均と偏差を計算の開始時間(datetime型)。最古の仮想取引まで加味するなら0。
                                                   mOpenTime - 1         // 指標の平均と偏差を計算の終了時間(datetime型)。
                                                  );
            bool flagRange[4];
            bool flagRangeOfBP = create_Stoc_vOrdersBUY_PROFIT(mStrategyID, mSymbol, mTimeFrame, mOpenTime, 0, mOpenTime - 1);
            flagRange[0] = flagRangeOfBP;
            bool flagRangeOfBL = create_Stoc_vOrdersBUY_LOSS(mStrategyID, mSymbol, mTimeFrame, mOpenTime, 0, mOpenTime - 1);
            flagRange[1] = flagRangeOfBL;
            bool flagRangeOfSP = create_Stoc_vOrdersSELL_PROFIT(mStrategyID, mSymbol, mTimeFrame, mOpenTime, 0, mOpenTime - 1);
            flagRange[2] = flagRangeOfSP;
            bool flagRangeOfSL = create_Stoc_vOrdersSELL_LOSS(mStrategyID, mSymbol, mTimeFrame, mOpenTime, 0, mOpenTime - 1);
            flagRange[3] = flagRangeOfSL;
            
            // 計算に失敗(BP, BL, SP, SLが全てfalse)した場合は、発注しない
            if(flagRangeOfBP    == false
               && flagRangeOfBL == false
               && flagRangeOfSP == false
               && flagRangeOfSL == false) {
               printf("[%d]VT 指標の平均と偏差。約定時間%sの仮想取引を発注しない。", __LINE__, TimeToStr(mOpenTime));
           }
            else  {
               // 計算に成功(flag_getStoc_vOrders==true)した場合は、
               // 現時点(i)の全指標が、過去の仮想取引から計算する指標が取りうる範囲内かどうかの判断をする。
               if(judgeTradable(OP_BUY, flagRange, mJudgeMethod, curr_st_vOrderIndex, positiveSigma, negativeSigma) == true)  {
                  mOpenprice = iClose(global_Symbol,0,i);
                  tickNo = v_mOrderSend4(mOpenTime, global_Symbol, OP_BUY,  LOTS, mOpenprice, SLIPPAGE, 0.0, 0.0, mStrategyID, 0, 0, LINE_COLOR_LONG);
                  if(tickNo > 0)  {
                     printf("[%d]VT v_mOrderSendBatchで仮想取引（買い）を追加。", __LINE__, TimeToStr(mOpenTime));
                     retCount++;
                  }
               }
               else  {
                  printf("[%d]VT 現時点(i)%sの条件を満たさないため仮想取引（買い）断念。", __LINE__, TimeToStr(mOpenTime)); 
               }
               // 判断結果がtrueであれば、判断した取引（買い（売り））を発注する。
               if(judgeTradable(OP_SELL, flagRange, mJudgeMethod, curr_st_vOrderIndex, positiveSigma, negativeSigma) == true)  {
                  mOpenprice = iClose(global_Symbol,0,i);
                  tickNo = v_mOrderSend4(mOpenTime, global_Symbol, OP_SELL, LOTS, mOpenprice, SLIPPAGE, 0.0, 0.0, mStrategyID, 0, 0, LINE_COLOR_SHORT);
                  if(tickNo > 0){
                     retCount++;
                     printf("[%d]VT v_mOrderSendBatchで仮想取引（売り）を追加。", __LINE__, TimeToStr(mOpenTime));
                  }
               }  // 判断結果がtrueであれば、判断した取引（買い（売り））を発注する。
               else  {
                 printf("[%d]VT 現時点(i)%sの条件を満たさないため仮想取引（売り）断念。", __LINE__, TimeToStr(mOpenTime)); 
               }
            }     // else {  // 計算に成功(flag_getStoc_vOrders==true)した場合
         }  // 現時点(i)の指標計算に成功した時、以下を行う。
      }     // else ←　仮想取引が0件より大。
   }           // for(i = mShiftFrom; i <= mShiftTo; i++) {

   return retCount;
}




//+----------------------------------------------------------------------+
//| 指標値と過去の平均、偏差を使って、売買可能かどうかを判断する。       |
//+---------------------------------------------------------------------+
// 引数flagBuySell(OP_BUY, OP_SELL)の売買が可能かどうかを、引数judgeMethodの基準で、
// 引数curr_st_vOrderIndexで渡した判断時点指標と、グローバル変数に格納済みの過去指標を使って
// 判断する。
// 引数flagRange[0]＝買い＆利益の平均、偏差計算済み。
// 引数flagRange[1]＝買い＆損失の平均、偏差計算済み。
// 引数flagRange[2]＝売り＆利益の平均、偏差計算済み。
// 引数flagRange[3]＝売り＆損失の平均、偏差計算済み。
// 
bool judgeTradable(int flagBuySell, 
                   bool &flagRange[], 
                   int judgeMethod, 
                   st_vOrderIndex &curr_st_vOrderIndex, 
                   double positiveSigma, 
                   double negativeSigma) {
   if(flagBuySell != OP_BUY && flagBuySell != OP_SELL)  {
      return false;
   }

   if(judgeMethod < 1 && judgeMethod > 3)  {
      return false;
   }

   if(positiveSigma < 0.0)  {
      return false;
   }

   if(negativeSigma < 0.0)  {
      return false;
   }

   bool tradableFlag = false;

   // 買い取引の判断
   if(flagBuySell == OP_BUY)  {
      // 判断パターン番号1：全ての項目が買い＆利益の範囲内の時、trueを返す。
      // st_vAnalyzedIndexesBUY_Profitが計算済みであること。
      if(judgeMethod == 1 
         && flagRange[0] == true)  {
         if(st_vAnalyzedIndexesBUY_Profit.analyzeTime <= 0)  {
            printf("[%d]VT st_vAnalyzedIndexesBUY_Profit.strategyIDが未計算（空欄）のため、買い判断不能", __LINE__);
            return false;
         }
         else {
            tradableFlag = isInsideOf(st_vAnalyzedIndexesBUY_Profit, positiveSigma, curr_st_vOrderIndex);
            if(tradableFlag == true)  {
               return true;
            }
         }
      }

      // 判断パターン番号2：全ての項目が買い＆損失の範囲外
      // st_vAnalyzedIndexesBUY_Lossが計算済みであること。
      if(judgeMethod == 2
         && flagRange[1] == true)  {
         if(st_vAnalyzedIndexesBUY_Loss.analyzeTime <= 0)  {
            printf("[%d]VT st_vAnalyzedIndexesBUY_Los.strategyIDが未計算（空欄）のため、買い判断不能", __LINE__);
            return false;
         }
         else {
            tradableFlag = isOutsideOf(st_vAnalyzedIndexesBUY_Loss, negativeSigma, curr_st_vOrderIndex);  
            if(tradableFlag == true)  {
               return true;
            }
         }
      }

      // 判断パターン番号3：1,2の両立。買い＆利益の範囲内であって、買い＆損失の範囲外。
      // st_vAnalyzedIndexesBUY_Profitが計算済みであること。
      // かつ、st_vAnalyzedIndexesBUY_Lossが計算済みであること。
      if(judgeMethod == 3
         && flagRange[0] == true
         && flagRange[1] == true) {
         if(st_vAnalyzedIndexesBUY_Profit.analyzeTime <= 0
            || st_vAnalyzedIndexesBUY_Loss.analyzeTime <= 0)  {
            printf("[%d]VT st_vAnalyzedIndexesBUY_Lossまたはst_vAnalyzedIndexesBUY_Lossが未計算（空欄）のため、買い判断不能", __LINE__);
            return false;
         }
         else {
            tradableFlag = isInsideOf(st_vAnalyzedIndexesBUY_Profit, positiveSigma, curr_st_vOrderIndex);
            if(tradableFlag == true)  {
               tradableFlag = isOutsideOf(st_vAnalyzedIndexesBUY_Loss, negativeSigma, curr_st_vOrderIndex);
               if(tradableFlag == true)  {
                  return true;
               }
            }
         }
      }      // if(judgeMethod == 3) {
   }         // if(flagBuySell == OP_BUY) {


   // 売り取引の判断
   if(flagBuySell == OP_SELL)  {
      // 判断パターン番号1：全ての項目が買い＆利益の範囲内の時、trueを返す。
      // st_vAnalyzedIndexesSELL_Profitが計算済みであること。
      
      if(judgeMethod == 1 
         && flagRange[2] == true)  {
         if(st_vAnalyzedIndexesSELL_Profit.analyzeTime <= 0)  {
            printf("[%d]VT st_vAnalyzedIndexesSELL_Profit.strategyIDが未計算（空欄）のため、売り判断不能", __LINE__);
            return false;
         }
         else {
            tradableFlag = isInsideOf(st_vAnalyzedIndexesSELL_Profit, positiveSigma, curr_st_vOrderIndex);
            
            if(tradableFlag == true)  {
               return true;
            }
         }
      }
      // 判断パターン番号2：全ての項目が買い＆損失の範囲外
      // st_vAnalyzedIndexesSELL_Lossが計算済みであること。
      if(judgeMethod == 2
         && flagRange[3] == true)  {
         if(st_vAnalyzedIndexesSELL_Loss.analyzeTime <= 0)  {
            printf("[%d]VT st_vAnalyzedIndexesSELL_Loss.strategyIDが未計算（空欄）のため、売り判断不能", __LINE__);
            return false;
         }
         else {
            tradableFlag = isOutsideOf(st_vAnalyzedIndexesSELL_Loss, negativeSigma, curr_st_vOrderIndex);
         
            if(tradableFlag == true)  {
               return true;
            }
         }
      }

      // 判断パターン番号3：1,2の両立。買い＆利益の範囲内であって、買い＆損失の範囲外。
      // st_vAnalyzedIndexesSELL_Profitが計算済みであること。
      // かつ、st_vAnalyzedIndexesSELL_Lossが計算済みであること。
      if(judgeMethod == 3
         && flagRange[2] == true
         && flagRange[3] == true) {
         if(st_vAnalyzedIndexesSELL_Profit.analyzeTime <= 0
            || st_vAnalyzedIndexesSELL_Loss.analyzeTime <= 0)  {
            printf("[%d]VT st_vAnalyzedIndexesSELL_Lossまたはst_vAnalyzedIndexesSELL_Lossが未計算（空欄）のため、売り判断不能", __LINE__);
            return false;
         }
         else {
            tradableFlag = isInsideOf(st_vAnalyzedIndexesSELL_Profit, positiveSigma, curr_st_vOrderIndex);
            if(tradableFlag == true)  {
               tradableFlag = isOutsideOf(st_vAnalyzedIndexesSELL_Loss, negativeSigma, curr_st_vOrderIndex);
               if(tradableFlag == true)  {
                  return true;
               }
            }
         }      
      }         // if(judgeMethod == 3) {
   }            // if(flagBuySell == OP_SELL) {

   return false;
}



// 構造体st_IndexRangeの各指標の各平均と偏差に対して、構造体curr_st_vOrderIndexの各指標の値が、
// 平均±mConst×偏差の範囲内であれば、trueを返す。
// ただし、構造体st_IndexRangeと構造体curr_st_vOrderIndexのどちらかの値がDOUBLE_VALUE_MIN又はINT_VALUE_MINの場合は、
// その項目は条件を満たしているものとする。
bool isInsideOf(st_vAnalyzedIndex &st_IndexRange,  // 過去データを基に計算した平均と偏差を持つ構造体。
                double mConst,                     // 偏差に掛ける数
                st_vOrderIndex &curr_st_vOrderIndex) {
   int satisfyPoint = 0;    // 判定したもののうち、条件を満たした項目数
   int satisfyPointALL = 0; // 判定した総数

   // キー項目が一致していることをチェックする。
   if(StringLen(st_IndexRange.symbol) > 0 && StringLen(curr_st_vOrderIndex.symbol) > 0 && StringCompare(st_IndexRange.symbol,curr_st_vOrderIndex.symbol) != 0) {
      printf("[%d]VTエラー キー項目symbol不一致 %s -- %s", __LINE__,st_IndexRange.symbol,curr_st_vOrderIndex.symbol);
      return false;
   }
   if(st_IndexRange.timeframe  != curr_st_vOrderIndex.timeframe) {
      printf("[%d]VTエラー キー項目timeframe不一致 %d -- %d", __LINE__, st_IndexRange.timeframe, curr_st_vOrderIndex.timeframe);
      return false;
   }
   if(st_IndexRange.analyzeTime > curr_st_vOrderIndex.calcTime)  {
      printf("[%d]VTエラー キー項目calcTime不整合 %sで計算した範囲に%sの値が入っているかを計算しようとした", __LINE__,
             TimeToStr(st_IndexRange.analyzeTime),
             TimeToStr(curr_st_vOrderIndex.calcTime));
      return false;
   }
   // 何も判断せず、trueを返すことを防ぐため、次の場合は、後続処理をせず、falseを返す。
   //  1) 構造体st_IndexRangeの各指標の各平均が全て、DOUBLE_VALUE_MIN
   //  2) 構造体st_IndexRangeの各指標の各偏差が全て、DOUBLE_VALUE_MIN
   //  3) 平均と偏差が、全てDOUBLE_VALUE_MIN）（上記1), 2)により、実現できるため、追加処理は不要）
   bool flag_check_st_vAnalyzedIndex = check_st_vAnalyzedIndex(st_IndexRange);
   if(flag_check_st_vAnalyzedIndex == false) {
      //  1) 構造体st_IndexRangeの各指標の各平均が全て、DOUBLE_VALUE_MIN
      //  2) 構造体st_IndexRangeの各指標の各偏差が全て、DOUBLE_VALUE_MIN
      // 上記いずれか、または、両方を満たすため、後続処理はしない
      printf("[%d]VTエラー 過去データを基に計算した平均と偏差を持つ構造体が異常値のため、isInsideOf処理失敗", __LINE__);
      
      return false;
   }
   

   bool judgeFlag = false;
   // 各項目で、
   // DOUBLE_VALUE_MIN又はINT_VALUE_MINの時は、何もせず次の項目を評価する。
   // →20220223訂正：全項目が、DOUBLE_VALUE_MIN又はINT_VALUE_MINの時は、falseを返す
   // 上記以外の時、構造体curr_st_vOrderIndexの値が平均±mSigma×偏差の範囲内の時は、何もせず次の項目を評価する。
   //               構造体curr_st_vOrderIndexの値が平均±mSigma×偏差の範囲外の時は、falseを返して、関数終了。
   // 最後まで、falseを返して関数終了でなければ、trueを返して、関数終了。
   //printf( "[%d]VT MA_GCの評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.MA_GC_MEAN, st_IndexRange.MA_GC_SIGMA, mConst, curr_st_vOrderIndex.MA_GC, "MA_GC");
   if(judgeFlag == false) {
      printf( "[%d]VT 範囲外。MA_GC" , __LINE__);
      satisfyPointALL++;
      // return false;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   judgeFlag = judgeInclude(st_IndexRange.MA_DC_MEAN, st_IndexRange.MA_DC_SIGMA, mConst, curr_st_vOrderIndex.MA_DC, "MA_DC");
   if(judgeFlag == false) {
      printf( "[%d]VT 範囲外。MA_DC" , __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   //printf( "[%d]VT MA_SLOPE5の評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.MA_Slope5_MEAN, st_IndexRange.MA_Slope5_SIGMA, mConst, curr_st_vOrderIndex.MA_Slope5, "MA_Slope5");
   if(judgeFlag == false) {
      printf( "[%d]VT 範囲外。MA_SLOPE5" , __LINE__);
      satisfyPointALL++;
      //return false;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   judgeFlag = judgeInclude(st_IndexRange.MA_Slope25_MEAN, st_IndexRange.MA_Slope25_SIGMA, mConst, curr_st_vOrderIndex.MA_Slope25, "MA_Slope25");
   if(judgeFlag == false) {
      printf( "[%d]VT キー項目不一致 MA_SLOPE25" , __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   judgeFlag = judgeInclude(st_IndexRange.MA_Slope75_MEAN, st_IndexRange.MA_Slope75_SIGMA, mConst, curr_st_vOrderIndex.MA_Slope75, "MA_Slope75");
   if(judgeFlag == false) {
      printf( "[%d]VT 範囲外。MA_SLOPE75" , __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   //printf( "[%d]VT BBの評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.BB_Width_MEAN, st_IndexRange.BB_Width_SIGMA, mConst, curr_st_vOrderIndex.BB_Width, "BB_Width");
   if(judgeFlag == false) {
      printf( "[%d]VT 範囲外。BB" , __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   //printf( "[%d]VT IK_TENの評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.IK_TEN_MEAN, st_IndexRange.IK_TEN_SIGMA, mConst, curr_st_vOrderIndex.IK_TEN, "IK_TEN");
   if(judgeFlag == false)  {
      printf( "[%d]VT 範囲外。IK_TEN" , __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   //printf( "[%d]VT IK_CHIの評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.IK_CHI_MEAN, st_IndexRange.IK_CHI_SIGMA, mConst, curr_st_vOrderIndex.IK_CHI, "IK_CHI");
   if(judgeFlag == false)  {
      printf( "[%d]VT 範囲外。IK_CHI" , __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   //printf( "[%d]VT IK_LEGの評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.IK_LEG_MEAN, st_IndexRange.IK_LEG_SIGMA, mConst, curr_st_vOrderIndex.IK_LEG, "IK_LEG");
   if(judgeFlag == false) {
      printf( "[%d]VT 範囲外。IK_LEG" , __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   //printf( "[%d]VT MACD_GCの評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.MACD_GC_MEAN, st_IndexRange.MACD_GC_SIGMA, mConst, curr_st_vOrderIndex.MACD_GC, "MACD_GC");
   if(judgeFlag == false) {
      printf( "[%d]VT 範囲外。MACD_GC" , __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   //printf( "[%d]VT MACD_DCの評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.MACD_DC_MEAN, st_IndexRange.MACD_DC_SIGMA, mConst, curr_st_vOrderIndex.MACD_DC, "MACD_DC");
   if(judgeFlag == false) {
      printf( "[%d]VT 範囲外。MACD_DC" , __LINE__);
      printf( "[%d]VT平均と偏差を取得した時間=%s  比較対象の計算時間=>%s<=>%d<" , __LINE__,
                TimeToStr(st_IndexRange.analyzeTime),
                TimeToStr(curr_st_vOrderIndex.calcTime), curr_st_vOrderIndex.calcTime);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   //printf( "[%d]VT RSIの評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.RSI_VAL_MEAN, st_IndexRange.RSI_VAL_SIGMA, mConst, curr_st_vOrderIndex.RSI_VAL, "RSI_VAL");
   if(judgeFlag == false){
      printf( "[%d]VT 範囲外。RSI" , __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   //printf( "[%d]VT STOCの評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.STOC_VAL_MEAN, st_IndexRange.STOC_VAL_SIGMA, mConst, curr_st_vOrderIndex.STOC_VAL, "STOC_VAL");
   if(judgeFlag == false) {
      printf( "[%d]VT 範囲外。STOC_VAL" , __LINE__);
      satisfyPointALL++;
//      return false;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   //printf( "[%d]VT STOC_GCの評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.STOC_GC_MEAN, st_IndexRange.STOC_GC_SIGMA, mConst, curr_st_vOrderIndex.STOC_GC, "STOC_GC");
   if(judgeFlag == false) {
      printf( "[%d]VT 範囲外。STOC_GC" , __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   //printf( "[%d]VT STOC_DCの評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.STOC_DC_MEAN, st_IndexRange.STOC_DC_SIGMA, mConst, curr_st_vOrderIndex.STOC_DC, "STOC_DC");
   if(judgeFlag == false) {
      printf( "[%d]VT 範囲外。STOC_DC" , __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   //printf( "[%d]VT RCIの評価" , __LINE__);
   judgeFlag = judgeInclude(st_IndexRange.RCI_VAL_MEAN, st_IndexRange.RCI_VAL_SIGMA, mConst, curr_st_vOrderIndex.RCI_VAL, "RCI_VAL");
   if(judgeFlag == false){
      printf( "[%d]VT 範囲外。RCI_VAL" , __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   if(satisfyPointALL <= 0) {
      return false;
   }
   else if(satisfyPoint / satisfyPointALL *100 >= MATCHINDEX_PER) {
      return true;
   }
   else {
      return false;
   }
}



//  引数で渡された構造体st_IndexRangeの各項目の値が、DOUBLE_VALUE_MINになっていればfalseを返す。
//  1) 構造体st_IndexRangeの各指標の各平均が全て、DOUBLE_VALUE_MIN
//  2) 構造体st_IndexRangeの各指標の各偏差が全て、DOUBLE_VALUE_MIN
//  3) 平均と偏差が、全てDOUBLE_VALUE_MIN）（上記1), 2)により、実現できるため、追加処理は不要）

bool check_st_vAnalyzedIndex(st_vAnalyzedIndex &vAnarizedIndex) {
   bool retMEAN = true;
   bool retSIGMA = true;   
   // 平均値のチェック
   if(NormalizeDouble(vAnarizedIndex.MA_GC_MEAN, 3)         == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_DC_MEAN, 3)      == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope5_MEAN, 3)  == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope25_MEAN, 3) == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope75_MEAN, 3) == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.BB_Width_MEAN, 3)   == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.IK_TEN_MEAN, 3)     == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.IK_CHI_MEAN, 3)     == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.IK_LEG_MEAN, 3)     == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope5_MEAN, 3)  == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope5_MEAN, 3)  == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope5_MEAN, 3)  == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope5_MEAN, 3)  == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MACD_GC_MEAN, 3)    == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MACD_DC_MEAN, 3)    == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.RSI_VAL_MEAN, 3)    == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.STOC_VAL_MEAN, 3)   == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.STOC_GC_MEAN, 3)    == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.STOC_DC_MEAN, 3)    == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.RCI_VAL_MEAN, 3)    == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      ) {
 //     printf( "[%d]エラーVT vAnarizedIndexの平均が全てDOUBLE_VALUE_MIN" , __LINE__);
      retMEAN = false;
   }
   // 偏差のチェック
   if(NormalizeDouble(vAnarizedIndex.MA_GC_SIGMA, 3)         == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_DC_SIGMA, 3)      == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope5_SIGMA, 3)  == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope25_SIGMA, 3) == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope75_SIGMA, 3) == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.BB_Width_SIGMA, 3)   == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.IK_TEN_SIGMA, 3)     == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.IK_CHI_SIGMA, 3)     == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.IK_LEG_SIGMA, 3)     == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope5_SIGMA, 3)  == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope5_SIGMA, 3)  == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope5_SIGMA, 3)  == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MA_Slope5_SIGMA, 3)  == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MACD_GC_SIGMA, 3)    == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.MACD_DC_SIGMA, 3)    == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.RSI_VAL_SIGMA, 3)    == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.STOC_VAL_SIGMA, 3)   == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.STOC_GC_SIGMA, 3)    == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.STOC_DC_SIGMA, 3)    == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      && NormalizeDouble(vAnarizedIndex.RCI_VAL_SIGMA, 3)    == NormalizeDouble(DOUBLE_VALUE_MIN, 3)
      ) {
      retSIGMA = false;
   }
   if(retMEAN == true && retSIGMA == true) {
      return true;
   }
   else {
    
      return false;
   }
}


// 構造体st_IndexRangeの各指標の各平均と偏差に対して、構造体curr_st_vOrderIndexの各指標の値が、
// 平均±mConst×偏差の範囲の外であれば、trueを返す。
// ただし、構造体st_IndexRangeと構造体curr_st_vOrderIndexのどちらかの値がDOUBLE_VALUE_MIN又はINT_VALUE_MINの場合は、
// その項目は条件を満たしているものとする。
bool isOutsideOf(st_vAnalyzedIndex &st_IndexRange, double mConst, st_vOrderIndex &curr_st_vOrderIndex)  {
   int satisfyPoint = 0;    // 判定したもののうち、条件を満たした項目数
   int satisfyPointALL = 0; // 判定した総数

   // キー項目が一致していることをチェックする。

   if(StringLen(st_IndexRange.symbol) > 0 && StringLen(curr_st_vOrderIndex.symbol) > 0 && StringCompare(st_IndexRange.symbol,curr_st_vOrderIndex.symbol) != 0)  {
      printf("[%d]VTエラー キー項目不一致 %s -- %s", __LINE__,st_IndexRange.symbol,curr_st_vOrderIndex.symbol);
      return false;
   }
   if(st_IndexRange.timeframe  != curr_st_vOrderIndex.timeframe)  {
      printf("[%d]VTエラー キー項目不一致 %d -- %d", __LINE__, st_IndexRange.timeframe, curr_st_vOrderIndex.timeframe);
      return false;
   }
   if(st_IndexRange.analyzeTime > curr_st_vOrderIndex.calcTime)  {
      printf("[%d]VTエラー キー項目不一致 %s -- %s", __LINE__,
             TimeToStr(st_IndexRange.analyzeTime),
             TimeToStr(curr_st_vOrderIndex.calcTime));
      return false;
   }

   bool judgeFlag = false;
   // 各項目で、
   // DOUBLE_VALUE_MIN又はINT_VALUE_MINの時は、何もせず次の項目を評価する。
   // 上記以外の時、構造体curr_st_vOrderIndexの値が平均±mSigma×偏差の範囲内の時は、何もせず次の項目を評価する。
   //               構造体curr_st_vOrderIndexの値が平均±mSigma×偏差の範囲外の時は、falseを返して、関数終了。
   // 最後まで、falseを返して関数終了でなければ、trueを返して、関数終了。
   judgeFlag = judgeNOTInclude(st_IndexRange.MA_GC_MEAN, st_IndexRange.MA_GC_SIGMA, mConst, curr_st_vOrderIndex.MA_GC, "MA_GC");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 MA_GC", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.MA_DC_MEAN, st_IndexRange.MA_DC_SIGMA, mConst, curr_st_vOrderIndex.MA_DC, "MA_DC");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 MA_DC", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.MA_Slope5_MEAN, st_IndexRange.MA_Slope5_SIGMA, mConst, curr_st_vOrderIndex.MA_Slope5, "MA_SLOPE5");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 MA_SLOPE5", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.MA_Slope25_MEAN, st_IndexRange.MA_Slope25_SIGMA, mConst, curr_st_vOrderIndex.MA_Slope25, "MA_SLOPE25");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 MA_SLOPE25", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.MA_Slope75_MEAN, st_IndexRange.MA_Slope75_SIGMA, mConst, curr_st_vOrderIndex.MA_Slope75, "MA_SLOPE75");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 MA_SLOPE75", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.BB_Width_MEAN, st_IndexRange.BB_Width_SIGMA, mConst, curr_st_vOrderIndex.BB_Width, "BB");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 BB", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.IK_TEN_MEAN, st_IndexRange.IK_TEN_SIGMA, mConst, curr_st_vOrderIndex.IK_TEN, "IK_TEN");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 IK_TEN", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.IK_CHI_MEAN, st_IndexRange.IK_CHI_SIGMA, mConst, curr_st_vOrderIndex.IK_CHI, "IK_CHI");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 IK_CHI", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.IK_LEG_MEAN, st_IndexRange.IK_LEG_SIGMA, mConst, curr_st_vOrderIndex.IK_LEG, "IK_LEG");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 IK_LEG", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.MACD_GC_MEAN, st_IndexRange.MACD_GC_SIGMA, mConst, curr_st_vOrderIndex.MACD_GC, "MACD_GC");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 MACD_GC", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.MACD_DC_MEAN, st_IndexRange.MACD_DC_SIGMA, mConst, curr_st_vOrderIndex.MACD_DC, "MACD_DC");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 MACD_DC", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.RSI_VAL_MEAN, st_IndexRange.RSI_VAL_SIGMA, mConst, curr_st_vOrderIndex.RSI_VAL, "RSI_VAL");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 RSI", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.STOC_VAL_MEAN, st_IndexRange.STOC_VAL_SIGMA, mConst, curr_st_vOrderIndex.STOC_VAL, "STOC_VAL");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 STOC_VAL", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.STOC_GC_MEAN, st_IndexRange.STOC_GC_SIGMA, mConst, curr_st_vOrderIndex.STOC_GC, "STOC_GC");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 STOC_GC", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.STOC_DC_MEAN, st_IndexRange.STOC_DC_SIGMA, mConst, curr_st_vOrderIndex.STOC_DC, "STOC_DC");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外 STOC_DC", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }


   judgeFlag = judgeNOTInclude(st_IndexRange.RCI_VAL_MEAN, st_IndexRange.RCI_VAL_SIGMA, mConst, curr_st_vOrderIndex.RCI_VAL, "RCI_VAL");
   if(judgeFlag == false)  {
      printf("[%d]VT 範囲外。RCI_VAL", __LINE__);
      satisfyPointALL++;
   }
   else {
      satisfyPoint++;
      satisfyPointALL++;
   }

   if(satisfyPointALL <= 0) {
      return false;
   }
   else if(satisfyPoint / satisfyPointALL *100 >= MATCHINDEX_PER) {
      return true;
   }
   else {
      return false;
   }
}

// 引数mComparedが、mMean±mConst*mSigmaの範囲内にあれば、trueを返す。
// mCompared、mMean、mSigmaのいずれかがDOUBLE_VALUE_MINの時は、trueを返す。
bool judgeNOTInclude(double mMean, double mSigma, double mConst, double mCompared, string mComment)    {
   if(mMean == DOUBLE_VALUE_MIN
      || mSigma == DOUBLE_VALUE_MIN
      ||  mCompared == DOUBLE_VALUE_MIN)  {
      return true;
   }
   else  {
      bool compareFlag = false;
      if(NormalizeDouble(mCompared, global_Digits) <  NormalizeDouble(mMean, global_Digits) - NormalizeDouble(mConst, global_Digits) * NormalizeDouble(mSigma, global_Digits))  {
         compareFlag =  true;
      }
      if(NormalizeDouble(mCompared, global_Digits) >  NormalizeDouble(mMean, global_Digits) + NormalizeDouble(mConst, global_Digits) * NormalizeDouble(mSigma, global_Digits))  {
         compareFlag =  true;
      }     
      
      if(compareFlag == false)  {
         printf("[%d]VT %sが範囲外ではない。", __LINE__, DoubleToStr(mCompared, global_Digits));
         printf("[%d]VT >%s<の評価値%sが範囲外ではない μ+nσ=%s μ-nσ=%s", __LINE__,
                mComment,
                DoubleToStr(mCompared, global_Digits),
                DoubleToStr(NormalizeDouble(mMean, global_Digits)+NormalizeDouble(mSigma, global_Digits)*mConst),
                DoubleToStr(NormalizeDouble(mMean, global_Digits)-NormalizeDouble(mSigma, global_Digits)*mConst)
               );
         printf("[%d]VT >%s<の評価値%sが範囲外ではない 各値は、μ=%s n=%s σ=%s", __LINE__,
                mComment,
                DoubleToStr(mCompared, global_Digits),
                DoubleToStr(NormalizeDouble(mMean, global_Digits)),
                DoubleToStr(NormalizeDouble(mConst, global_Digits)),
                DoubleToStr(NormalizeDouble(mSigma, global_Digits))
               );
         return false;
      }
      else  {
         /// 範囲内にあるため、次の項目へ。
      }
   }

   return true;
}


// 引数m_vOPENTIME=st_vOrders[i].openTimeを満たす仮想取引が存在すれば、trueを返す。
bool exist_vOrder(datetime m_vOpentime)  {
   if(m_vOpentime < 0){
      return false;
   }

   for(int i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }

      if(st_vOrders[i].openTime == m_vOpentime) {
         return true;
      }
   }

   return false;
}


//+------------------------------------------------------------------+
//| 仮想取引約定時点の各種指標を計算する。　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　　|
//+------------------------------------------------------------------+
// 登録済み仮想取引から抽出した戦略、通貨ペア、時間軸、基準時間で各指標を計算し、
// グローバル変数st_vOrderIndexes[]の空いた場所に格納する。
   string   v_buf_strategyID[VTRADENUM_MAX];
   string   v_buf_symbol[VTRADENUM_MAX];
   int      v_buf_timeframe[VTRADENUM_MAX];
   datetime v_buf_openTime[VTRADENUM_MAX];
   
bool v_calcIndexes()  {
// 各種指標を計算する基準時間とその他キーを取得するため、
// 登録済み仮想取引st_vOrders[i]に存在するデータの組み合わせを検索する。
// 検索キーは、
// string strategyID       // VTなど
// string symbol;          // EURUSD-CDなど
// int    timeframe;       // 時間軸。0は不可。
// datetime openTime       // 約定日時。


   int i;
   int j;
   int k;
   bool     buf_existFlag = false;

   // 各種指標を計算する基準時間とその他キーを格納する配列buf_*の初期化。
   for(i = 0; i < VTRADENUM_MAX; i++) {
      v_buf_strategyID[i] = "";
      v_buf_symbol[i] = "";
   }

   ArrayInitialize(v_buf_timeframe, 0);
   ArrayInitialize(v_buf_openTime, 0);
   
   int countOFvTrade = 0; //　該当する仮想取引数のカウンタ。

   // 仮想取引全件を見て、各種指標を計算する基準時間とその他キーを取得する。
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0) { 
         break;
      }

      if(st_vOrders[i].openTime > 0) {  // 有効な仮想取引に対してのみ、以下を行う。
         countOFvTrade++;
         // ループ中の仮想取引st_vOrders[i]の指標計算向けキーの組み合わせをbuf_*内に登録する。
         for(j = 0; j < VTRADENUM_MAX; j++) {
         // buf_strategyID[j], buf_timeframe[j], buf_openTime[j]とキーが一致すれば(buf_existFlag = true)、追加不要。
         // buf_existFlag = falseのままなら、仮想取引st_vOrders[i]のキーを新規追加する。
            buf_existFlag = false;  // 検索したデータの組み合わせがbuf_*内に登録済みであれば、trueにする。
            if(j != i
               && StringLen(v_buf_strategyID[j]) > 0 && StringLen(st_vOrders[i].strategyID) > 0 && StringCompare(v_buf_strategyID[j], st_vOrders[i].strategyID) == 0
               && StringLen(v_buf_symbol[j]) > 0 && StringLen(st_vOrders[i].symbol) > 0 && StringCompare(v_buf_symbol[j], st_vOrders[i].symbol) == 0
               && v_buf_timeframe[j] == st_vOrders[i].timeframe
               && v_buf_openTime[j] == st_vOrders[i].openTime)  {
               buf_existFlag = true; // 検索したデータの組み合わせがbuf_*内に登録済み
               break;
            }
         }

         // 注目している仮想取引から抽出したキー項目が、発見済みのキーの組み合わせ
         // buf_strategyID[j], buf_timeframe[j], buf_openTime[j]の中に存在していないので新規追加
         if(buf_existFlag == false)  {
            bool insert_buf_flag = false; // 新規追加に成功したらtrueに変更する。
            // buf_*内の空きを探す。
            for(k = 0; k < VTRADENUM_MAX; k++) {
               if(v_buf_openTime[k] == 0)  {
                  // 空きを発見できたので、新規追加
                  v_buf_strategyID[k] = st_vOrders[i].strategyID;
                  v_buf_symbol[k]     = st_vOrders[i].symbol;
                  v_buf_timeframe[k]  = st_vOrders[i].timeframe;
                  v_buf_openTime[k]   = st_vOrders[i].openTime;
                  insert_buf_flag     = true;
                  break;
               }
            }

            // 追加に失敗していたらエラーを出力して処理を中断する。
            if(insert_buf_flag == false) {
               printf("[%d]エラーVT 指標評価キーの抽出に失敗", __LINE__);
               return false;
            }
         } // if(buf_existFlag == false)  {
      }    //  if(st_vOrders[i].openTime > 0) {
   }       // for(i = 0; i < VTRADENUM_MAX; i++) {

   // この行までに、仮想取引全件を見て取得した、各種指標のキーがbuf_strategyID[j], buf_timeframe[j], buf_openTime[j]に入っている。
   // これらのキーを使って、指標を計算する。
   // 有効な仮想取引が1件も無ければ、falseを返して、処理を終了する。
   if(countOFvTrade == 0) {
      return false;
   }
   
   bool retFlag = false;  // 1件でもv_calcIndexesが成功したら、trueとする。
   for(i = 0; i < VTRADENUM_MAX; i++)  {
      if(v_buf_openTime[i] <= 0)  {
         break;
      }
      if(v_buf_openTime[i] > 0)  {
         bool flag_v_calcIndexes = 
         v_calcIndexes(v_buf_strategyID[i],
                       v_buf_symbol[i],
                       v_buf_timeframe[i],
                       v_buf_openTime[i]);
         if(flag_v_calcIndexes == true) {
            retFlag = true;
         }
      }
   }
   if(retFlag == false) {  // 全てのキー項目に対するv_calcIndexesが失敗したら、falseを返して、処理を終了する。
      return false;
   }
   return true;
}

// 引数で指定した戦略、通貨ペア、時間軸、基準時間で各指標を計算し、
// 引数m_st_vOrderIndexに格納する。
// ※グローバル変数st_vOrderIndexes[]の空いた場所に格納する関数は、別途定義している。
// 引数mCalcTimeが、指標を計算する基準時間。
// 何からの計算に失敗した場合は、falseを返す。それ以外は、true。
bool v_calcIndexes(string mStrategyID,                // 入力：戦略名
                   string mSymbol,                    // 入力：通貨ペア
                   int mTimeframe_calc,                    // 入力：時間軸。PERIOD_M15。
                   datetime mCalcTime,                // 入力：計算基準日
                   st_vOrderIndex &m_st_vOrderIndex)  // 出力：計算結果を格納する構造体
  {
   if(StringLen(mStrategyID) <= 0)  {
      return false;
   }
   if(mTimeframe_calc < 0) {
      return false;
   }

   // 指定したオープン時間を持つバーが存在しない場合は、チャート上に存在するバーの近い時間のバーシフト。
   //  mCalcShift = iBarShift(global_Symbol, 0, mCalcTime, false);


// 参考：iBarShiftは、true:指定した時間のバーが存在しない場合、-1を返す。
   int i;
   bool flag = false;
// st_vOrderIndexes[]を引数で検索し、登録済みの場合は指標の計算をしない。
// →　引数m_st_vOrderIndexに計算済み指標値をコピーする。

   bool buf_existFlag = false;
   int  buf_Index = -1;

   for(i = 0; i < VTRADENUM_MAX; i++)  {
      if(st_vOrderIndexes[i].calcTime <= 0) {
         break;
      }

      if(StringLen(st_vOrderIndexes[i].symbol) > 0 && StringLen(mSymbol) > 0 && StringCompare(st_vOrderIndexes[i].symbol, mSymbol) == 0
         && st_vOrderIndexes[i].timeframe == mTimeframe_calc
         && st_vOrderIndexes[i].calcTime == mCalcTime)  {
         //キーが一致するデータが存在する
         buf_existFlag = true;
         buf_Index = i;
         break;
      }
   }

   // 計算済みのため、再計算は不要。値をm_st_vOrderIndexにコピーして正常終了する。
   if(buf_existFlag == true && buf_Index > 0)  {
      bool flag_copy_st_vOrderIndex = copy_st_vOrderIndex(st_vOrderIndexes[buf_Index], m_st_vOrderIndex);
      if(flag_copy_st_vOrderIndex == true) {
         return true;
      }
   }

   // 指標を計算し、m_st_vOrderIndexに代入する。
   bool flag_do_calc_Indexes = do_calc_Indexes(mSymbol, mTimeframe_calc, mCalcTime, m_st_vOrderIndex);
   if(flag_do_calc_Indexes == false) {
      return false;
   }
   else {
      return true;
   }
   
   // いづれのパスも通らなかった場合は、異常終了のため、falseを返す。
   return false;
}



// 仮想取引を格納したst_vOrder型構造体のデータをコピーする
// 【注意】コピー後に、コピー元のデータを削除する時は、別途、削除処理をすること
bool copy_st_vOrder(st_vOrder &From_st_vOrder,  // コピー元 
                    st_vOrder &To_st_vOrder     // コピー先
   )  {
   To_st_vOrder.externalParam = From_st_vOrder.externalParam;   // 仮想最適化の場合のみ利用する。^区切りの外部パラメータ。
   To_st_vOrder.strategyID = From_st_vOrder.strategyID;      // 21:RCISWING, 20:TrendBB, 19:MoveSpeedなど
   To_st_vOrder.symbol = From_st_vOrder.symbol;          // EURUSD-CDなど
   To_st_vOrder.ticket = From_st_vOrder.ticket;          // 通し番号
   To_st_vOrder.timeframe = From_st_vOrder.timeframe;       // 【参考情報であり使い道無し】仮想取引を発注する際に用いた時間軸。時間軸。0は不可。
   To_st_vOrder.orderType = From_st_vOrder.orderType;       // OP_BUYかOPSELL
   To_st_vOrder.openTime = From_st_vOrder.openTime;        // 約定日時。datetime型。
   To_st_vOrder.lots = From_st_vOrder.lots;            // ロット数
   To_st_vOrder.openPrice = From_st_vOrder.openPrice;       // 新規建て時の値
   To_st_vOrder.orderTakeProfit = From_st_vOrder.orderTakeProfit; // 利益確定の値
   To_st_vOrder.orderStopLoss = From_st_vOrder.orderStopLoss;   // 損切の値
   To_st_vOrder.closePrice = From_st_vOrder.closePrice;      // 決済値
   To_st_vOrder.closeTime = From_st_vOrder.closeTime;       // 決済日時。datetime型。
   To_st_vOrder.closePL = From_st_vOrder.closePL;         // 決済損益
   To_st_vOrder.estimatePrice = From_st_vOrder.estimatePrice;   // 評価値
   To_st_vOrder.estimateTime = From_st_vOrder.estimateTime;    // 評価日時。datetime型。
   To_st_vOrder.estimatePL = From_st_vOrder.estimatePL;      // 評価損益

   return true;
}




// 指標を格納したst_vOrderIndex型構造体のデータをコピーする
// 【注意】コピー後に、コピー元のデータを削除する時は、別途、削除処理をすること
bool copy_st_vOrderIndex(st_vOrderIndex &From_st_vOrderIndex, st_vOrderIndex &To_st_vOrderIndex)  {
   To_st_vOrderIndex.symbol     = From_st_vOrderIndex.symbol  ;
   To_st_vOrderIndex.timeframe  = From_st_vOrderIndex.timeframe  ;
   To_st_vOrderIndex.calcTime   = From_st_vOrderIndex.calcTime  ;
   To_st_vOrderIndex.MA_GC      = From_st_vOrderIndex.MA_GC  ;
   To_st_vOrderIndex.MA_DC      = From_st_vOrderIndex.MA_DC  ;
   To_st_vOrderIndex.MA_Slope5  = NormalizeDouble(From_st_vOrderIndex.MA_Slope5, global_Digits)  ;
   To_st_vOrderIndex.MA_Slope25 = NormalizeDouble(From_st_vOrderIndex.MA_Slope25, global_Digits)   ;
   To_st_vOrderIndex.MA_Slope75 = NormalizeDouble(From_st_vOrderIndex.MA_Slope75, global_Digits)  ;
   To_st_vOrderIndex.BB_Width   = NormalizeDouble(From_st_vOrderIndex.BB_Width, global_Digits)  ;
   To_st_vOrderIndex.IK_TEN     = NormalizeDouble(From_st_vOrderIndex.IK_TEN, global_Digits)  ;
   To_st_vOrderIndex.IK_CHI     = NormalizeDouble(From_st_vOrderIndex.IK_CHI, global_Digits)  ;
   To_st_vOrderIndex.IK_LEG     = NormalizeDouble(From_st_vOrderIndex.IK_LEG, global_Digits)  ;
   To_st_vOrderIndex.MACD_GC    = From_st_vOrderIndex.MACD_GC  ;
   To_st_vOrderIndex.MACD_DC    = From_st_vOrderIndex.MACD_DC  ;
   To_st_vOrderIndex.RSI_VAL    = NormalizeDouble(From_st_vOrderIndex.RSI_VAL, global_Digits)  ;
   To_st_vOrderIndex.STOC_VAL   = NormalizeDouble(From_st_vOrderIndex.STOC_VAL, global_Digits)  ;
   To_st_vOrderIndex.STOC_GC    = From_st_vOrderIndex.STOC_GC  ;
   To_st_vOrderIndex.STOC_DC    = From_st_vOrderIndex.STOC_DC  ;
   To_st_vOrderIndex.RCI_VAL    = NormalizeDouble(From_st_vOrderIndex.RCI_VAL, global_Digits)  ;

   return true;
}


// 評価結果を格納したst_vOrderPL型構造体のデータをコピーする
bool copy_st_vOrderPL(st_vOrderPL &From_st_vOrderPL, // コピー元
                      st_vOrderPL &To_st_vOrderPL    // コピー先
                      ) {
   To_st_vOrderPL.strategyID  = From_st_vOrderPL.strategyID;
   To_st_vOrderPL.symbol      = From_st_vOrderPL.symbol;
   To_st_vOrderPL.timeframe   = From_st_vOrderPL.timeframe;
   To_st_vOrderPL.analyzeTime = From_st_vOrderPL.analyzeTime;
   To_st_vOrderPL.win         = From_st_vOrderPL.win;
   To_st_vOrderPL.Profit      = From_st_vOrderPL.Profit;
   To_st_vOrderPL.lose        = From_st_vOrderPL.lose;
   To_st_vOrderPL.Loss        = From_st_vOrderPL.Loss;
   To_st_vOrderPL.even        = From_st_vOrderPL.even;
   To_st_vOrderPL.maxDrawdownPIPS = From_st_vOrderPL.maxDrawdownPIPS ;
   To_st_vOrderPL.riskRewardRatio = From_st_vOrderPL.riskRewardRatio;
   To_st_vOrderPL.ProfitFactor    = From_st_vOrderPL.ProfitFactor;

   for(int i = 0; i < HISTORICAL_NUM; i++ ) {
      To_st_vOrderPL.latestTrade_time[i] = From_st_vOrderPL.latestTrade_time[i];
      To_st_vOrderPL.latestTrade_PL[i] = From_st_vOrderPL.latestTrade_PL[i];
   }
   To_st_vOrderPL.latestTrade_WeightedAVG = From_st_vOrderPL.latestTrade_WeightedAVG;
   return true;
}

// 評価結果を格納したst_vOrderPL型構造体配列のデータをコピーする
bool copy_st_vOrderPL(st_vOrderPL &From_st_vOrderPLs[], st_vOrderPL &To_st_vOrderPLs[]) {
   // コピー先のTo_st_vOrderPLs[]を初期化
   init_st_vOrderPLs(To_st_vOrderPLs);
   
   int i; 
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(From_st_vOrderPLs[i].analyzeTime <= 0) {
         break;
      }
      copy_st_vOrderPL(From_st_vOrderPLs[i], To_st_vOrderPLs[i]);
   }

   return true;
}


// PBのパラメータセットを格納したst_25PinOptParamr型構造体のデータをコピーする
// 【注意】コピー後に、コピー元のデータを削除する時は、別途、削除処理をすること
bool copy_st_25PinOptParam(st_25PinOptParam &From_st_25PinOptParam,  // コピー元 
                           st_25PinOptParam &To_st_25PinOptParam     // コピー先
   )  {
   To_st_25PinOptParam.strategyID            = From_st_25PinOptParam.strategyID ;           // g_StratNameNN + 戦略別通し番号"@@NNNNN"とする。例えば、25PIN@@00001
   To_st_25PinOptParam.TP_PIPS               = From_st_25PinOptParam.TP_PIPS;               //【最適化:5.0～100.0。+5する＝×20】1約定あたりの利確pips数。負の時は、利確値の設定や強制利確をしない。
   To_st_25PinOptParam.SL_PIPS               = From_st_25PinOptParam.SL_PIPS;               //【実装保留】1約定当たりの損切pips数。SL_PIPS_PER設定時は上書きされる。負の時は、損切値の設定や強制損切をしない。
   To_st_25PinOptParam.SL_PIPS_PER           = From_st_25PinOptParam.SL_PIPS_PER;           //【最適化:10.0～30.0。+10する＝×3】TP_PIPSに対するSL_PPIPSの割りあい。SL_PIPSを上書きする。負の時は、上書きしない。
   To_st_25PinOptParam.FLOORING              = From_st_25PinOptParam.FLOORING;              //【実装保留】損切値を、オープンから指定した値(PIP)の位置に変更する。PIPS数。負の数の場合は、何もしない。            
   To_st_25PinOptParam.FLOORING_CONTINUE     = From_st_25PinOptParam.FLOORING_CONTINUE;     //【実装保留】trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。    
   To_st_25PinOptParam.TIME_FRAME_MAXMIN     = From_st_25PinOptParam.TIME_FRAME_MAXMIN;     //【実装保留】1～9最高値、最安値の参照期間の単位。
   To_st_25PinOptParam.SHIFT_SIZE_MAXMIN     = From_st_25PinOptParam.SHIFT_SIZE_MAXMIN;     //【実装保留】最高値、最安値の参照期間
   To_st_25PinOptParam.ENTRY_WIDTH_PIPS      = From_st_25PinOptParam.ENTRY_WIDTH_PIPS;      //【実装保留】エントリーする間隔。PIPS数。
   To_st_25PinOptParam.SHORT_ENTRY_WIDTH_PER = From_st_25PinOptParam.SHORT_ENTRY_WIDTH_PER; //【実装保留】ショート実施帯域。過去最高値から何パーセント下までショートするか
   To_st_25PinOptParam.LONG_ENTRY_WIDTH_PER  = From_st_25PinOptParam.LONG_ENTRY_WIDTH_PER;  //【実装保留】ロング実施帯域。過去最安値から何パーセント上までロングするか
   To_st_25PinOptParam.ALLOWABLE_DIFF_PER    = From_st_25PinOptParam.ALLOWABLE_DIFF_PER;    //【実装保留】価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値みなすか。 
   To_st_25PinOptParam.PinBarMethod          = From_st_25PinOptParam.PinBarMethod;          //【最適化:1～7】001(1)=No1, 010(2)=No3, 011(3)=No1とNo3, 100(4)=No5, 101(5)=No1とNo5, 110(6)=No3とNo5, 111=No1とNo3とNo5
   To_st_25PinOptParam.PinBarTimeframe       = From_st_25PinOptParam.PinBarTimeframe;       //【変動させない】ピンの計算に使う時間軸
   To_st_25PinOptParam.PinBarBackstep        = From_st_25PinOptParam.PinBarBackstep;        //【変動させない】大陽線、大陰線が発生したことを何シフト前まで確認するか
   To_st_25PinOptParam.PinBarBODY_MIN_PER    = From_st_25PinOptParam.PinBarBODY_MIN_PER;    //【最適化:60.0～90.0。+10する＝×4】実体が髭のナンパ―セント以上であれば陽線、陰線と判断するか
   To_st_25PinOptParam.PinBarPIN_MAX_PER     = From_st_25PinOptParam.PinBarPIN_MAX_PER;     //【最適化:10.0～30.0。+5する ＝×5】実体が髭のナンパ―セント以下であればピンと判断するか

   return true;
}

// PBのパラメータセットを格納したst_25PinOptParamr型構造体のデータをコピーする
// 【注意】コピー後に、コピー元のデータを削除する時は、別途、削除処理をすること
bool copy_st_18CORROptParam(st_18CORROptParam &From_st_18CORROptParam,  // コピー元 
                            st_18CORROptParam &To_st_18CORROptParam     // コピー先
   )  {
   To_st_18CORROptParam.strategyID            = From_st_18CORROptParam.strategyID ;           // g_StratNameNN + 戦略別通し番号"@@NNNNN"とする。例えば、18CORR@@00001
   To_st_18CORROptParam.TP_PIPS               = From_st_18CORROptParam.TP_PIPS;               //【最適化:5.0～100.0。+5する＝×20】1約定あたりの利確pips数。負の時は、利確値の設定や強制利確をしない。
   To_st_18CORROptParam.SL_PIPS               = From_st_18CORROptParam.SL_PIPS;               //【実装保留】1約定当たりの損切pips数。SL_PIPS_PER設定時は上書きされる。負の時は、損切値の設定や強制損切をしない。
   To_st_18CORROptParam.SL_PIPS_PER           = From_st_18CORROptParam.SL_PIPS_PER;           //【最適化:10.0～30.0。+10する＝×3】TP_PIPSに対するSL_PPIPSの割りあい。SL_PIPSを上書きする。負の時は、上書きしない。
   To_st_18CORROptParam.FLOORING              = From_st_18CORROptParam.FLOORING;              //【実装保留】損切値を、オープンから指定した値(PIP)の位置に変更する。PIPS数。負の数の場合は、何もしない。            
   To_st_18CORROptParam.FLOORING_CONTINUE     = From_st_18CORROptParam.FLOORING_CONTINUE;     //【実装保留】trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。    
   To_st_18CORROptParam.TIME_FRAME_MAXMIN     = From_st_18CORROptParam.TIME_FRAME_MAXMIN;     //【実装保留】1～9最高値、最安値の参照期間の単位。
   To_st_18CORROptParam.SHIFT_SIZE_MAXMIN     = From_st_18CORROptParam.SHIFT_SIZE_MAXMIN;     //【実装保留】最高値、最安値の参照期間
   To_st_18CORROptParam.ENTRY_WIDTH_PIPS      = From_st_18CORROptParam.ENTRY_WIDTH_PIPS;      //【実装保留】エントリーする間隔。PIPS数。
   To_st_18CORROptParam.SHORT_ENTRY_WIDTH_PER = From_st_18CORROptParam.SHORT_ENTRY_WIDTH_PER; //【実装保留】ショート実施帯域。過去最高値から何パーセント下までショートするか
   To_st_18CORROptParam.LONG_ENTRY_WIDTH_PER  = From_st_18CORROptParam.LONG_ENTRY_WIDTH_PER;  //【実装保留】ロング実施帯域。過去最安値から何パーセント上までロングするか
   To_st_18CORROptParam.ALLOWABLE_DIFF_PER    = From_st_18CORROptParam.ALLOWABLE_DIFF_PER;    //【実装保留】価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値みなすか。 
   To_st_18CORROptParam.CORREL_TF_SHORTER          = From_st_18CORROptParam.CORREL_TF_SHORTER;
   To_st_18CORROptParam.CORREL_TF_LONGER       = From_st_18CORROptParam.CORREL_TF_LONGER;    
   To_st_18CORROptParam.CORRELLower        = From_st_18CORROptParam.CORRELLower;  
   To_st_18CORROptParam.CORRELHigher    = From_st_18CORROptParam.CORRELHigher;  
   To_st_18CORROptParam.CORREL_period     = From_st_18CORROptParam.CORREL_period;
   return true;
}


bool copy_st_08WPROptParam(st_08WPROptParam &From_st_08WPROptParam,  // コピー元 
                            st_08WPROptParam &To_st_08WPROptParam     // コピー先
   )  {
   To_st_08WPROptParam.strategyID            = From_st_08WPROptParam.strategyID ;           // g_StratNameNN + 戦略別通し番号"@@NNNNN"とする。例えば、08WPR@@00001
   To_st_08WPROptParam.TP_PIPS               = From_st_08WPROptParam.TP_PIPS;               //【最適化:5.0～100.0。+5する＝×20】1約定あたりの利確pips数。負の時は、利確値の設定や強制利確をしない。
   To_st_08WPROptParam.SL_PIPS               = From_st_08WPROptParam.SL_PIPS;               //【実装保留】1約定当たりの損切pips数。SL_PIPS_PER設定時は上書きされる。負の時は、損切値の設定や強制損切をしない。
   To_st_08WPROptParam.SL_PIPS_PER           = From_st_08WPROptParam.SL_PIPS_PER;           //【最適化:10.0～30.0。+10する＝×3】TP_PIPSに対するSL_PPIPSの割りあい。SL_PIPSを上書きする。負の時は、上書きしない。
   To_st_08WPROptParam.FLOORING              = From_st_08WPROptParam.FLOORING;              //【実装保留】損切値を、オープンから指定した値(PIP)の位置に変更する。PIPS数。負の数の場合は、何もしない。            
   To_st_08WPROptParam.FLOORING_CONTINUE     = From_st_08WPROptParam.FLOORING_CONTINUE;     //【実装保留】trueの時、繰り返し切り上げを行う。falseの時、損切値が損失を生む時のみ切り上げを行う。    
   To_st_08WPROptParam.TIME_FRAME_MAXMIN     = From_st_08WPROptParam.TIME_FRAME_MAXMIN;     //【実装保留】1～9最高値、最安値の参照期間の単位。
   To_st_08WPROptParam.SHIFT_SIZE_MAXMIN     = From_st_08WPROptParam.SHIFT_SIZE_MAXMIN;     //【実装保留】最高値、最安値の参照期間
   To_st_08WPROptParam.ENTRY_WIDTH_PIPS      = From_st_08WPROptParam.ENTRY_WIDTH_PIPS;      //【実装保留】エントリーする間隔。PIPS数。
   To_st_08WPROptParam.SHORT_ENTRY_WIDTH_PER = From_st_08WPROptParam.SHORT_ENTRY_WIDTH_PER; //【実装保留】ショート実施帯域。過去最高値から何パーセント下までショートするか
   To_st_08WPROptParam.LONG_ENTRY_WIDTH_PER  = From_st_08WPROptParam.LONG_ENTRY_WIDTH_PER;  //【実装保留】ロング実施帯域。過去最安値から何パーセント上までロングするか
   To_st_08WPROptParam.ALLOWABLE_DIFF_PER    = From_st_08WPROptParam.ALLOWABLE_DIFF_PER;    //【実装保留】価格が、エントリー間隔ENTRY_WIDTH_PIPSに対して、何％前後までは同じ値みなすか。 
   To_st_08WPROptParam.WPRLow                = From_st_08WPROptParam.WPRLow;
   To_st_08WPROptParam.WPRHigh               = From_st_08WPROptParam.WPRHigh;    
   To_st_08WPROptParam.WPRgarbage            = From_st_08WPROptParam.WPRgarbage;  
   To_st_08WPROptParam.WPRgarbageRate        = From_st_08WPROptParam.WPRgarbageRate;  
   return true;
}

// 引数で指定した戦略、通貨ペア、時間軸、基準時間で各指標を計算し、
// グローバル変数st_vOrderIndexes[]の空いた場所に格納する。
// 引数mCalcTimeが、指標を計算する基準時間。
// 何らかの計算に失敗した場合は、falseを返す。それ以外は、true。
bool v_calcIndexes(string mStrategyID, 
                   string mSymbol, 
                   int mTimeframe_calc, 
                   datetime mCalcTime) {
//   int mCalcShift = 0; // 引数mCalcTimeをオープン時間に持つオープン時間のバーシフト。
   if(StringLen(mStrategyID) <= 0)  {
      return false;
   }
   if(mTimeframe_calc < 0) {
      return false;
   }

   int i;
   bool flag = false;

   // st_vOrderIndexes[]を引数で検索し、登録済みの場合は指標の計算をしない。
   bool buf_existFlag = false;
   for(i = 0; i < VTRADENUM_MAX; i++)  {
      if(st_vOrderIndexes[i].calcTime <= 0) {
         break;
      }

      if(StringLen(st_vOrderIndexes[i].symbol) > 0 && StringLen(mSymbol) > 0 && StringCompare(st_vOrderIndexes[i].symbol, mSymbol) == 0
         && st_vOrderIndexes[i].timeframe == mTimeframe_calc
         && st_vOrderIndexes[i].calcTime == mCalcTime)  {
         //キーが一致するデータが存在する
         buf_existFlag = true;
         break;
      }
   }
   if(buf_existFlag == true) {
      // 計算済みのため、再計算は不要。正常終了する。
      return true;
   }

   //
   // st_vOrderIndexes[]を引数で検索し、新規追加する処理は以下のとおり。
   //
   int newIndex = 0;
   // 指標を計算して、st_vOrderIndexesの最初の空きに、代入する。
   buf_existFlag = false; // st_vOrderIndexesに空きを見つけたらtrueとする。
   for(i = 0; i < VTRADENUM_MAX; i++)  {
      if(st_vOrderIndexes[i].calcTime == 0)  {
         buf_existFlag = true;
         newIndex = i;
         break;
      }
   }

   if(buf_existFlag == false)  {
      // 指標の計算結果を格納する場所がないため、異常終了する。
      printf("[%d]エラーVT 指標評価計算結果を保存できません。", __LINE__);
      return false;
   }

   // 指標を計算し、空き場所st_vOrderIndexes[newIndex]に代入する。
   bool flag_do_calc_Indexes = do_calc_Indexes(mSymbol, mTimeframe_calc, mCalcTime, st_vOrderIndexes[newIndex]);
   if(flag_do_calc_Indexes == false) {
      return false;
   }

   return true;
}


// 引数で指定した戦略、通貨ペア、時間軸、基準時間で各指標を計算し、
// 引数m_st_vOrderIndexに格納する。
// 全ての項目で計算に失敗したら、falseを返す
double do_calc_Indexes_mData[VTRADENUM_MAX];
bool do_calc_Indexes(string   mSymbol,     // 入力：指標の計算対象通貨ペア 
                     int      mTimeframe_calc,  // 入力：PERIOD_M15。指標を計算する時に使う時間軸
                     datetime mCalcTime,   // 入力：計算基準時間
                     st_vOrderIndex &m_st_vOrderIndex  // 出力：計算結果の指標を入れる構造体
                     ) {
   // キー項目を初期化する。
   // 全ての項目で計算失敗したら、初期化のまま。1つでも計算できた項目があれば、最後にキー項目をセットする。
   m_st_vOrderIndex.symbol     = "";
   m_st_vOrderIndex.timeframe  = -1;
   m_st_vOrderIndex.calcTime   = -1;
   
   bool retFlag = false; // 一つでも項目の計算に成功したら、trueとする。 ＝　falseのままであれば、全ての項目の計算に失敗。
   // 指標を計算する基準時間が含まれるシフト番号
   int    mCalcShift   = iBarShift(mSymbol, mTimeframe_calc, mCalcTime, false);

   // 指標を計算する基準時間が含まれるシフトの終値
   double bufClosePrice = iClose(mSymbol,mTimeframe_calc,mCalcShift);  


// 1 移動平均:MA
   int mGC = 0;
   int mDC = 0;
   m_st_vOrderIndex.MA_GC = INT_VALUE_MIN;
   m_st_vOrderIndex.MA_DC = INT_VALUE_MIN;
   bool flag = getLastMA_Cross(mTimeframe_calc, mCalcShift, mGC, mDC) ;
   if(flag == true)  {
      m_st_vOrderIndex.MA_GC = mGC;
      m_st_vOrderIndex.MA_DC = mDC;
      // 一つでも項目の計算に成功したら、trueとする。
      retFlag = true;
   }

   double mSlope = 0.0;
   double mIntercept = 0.0;
   int    mDataNum = 0;
   int    i = 0;

   // シフト5本分の移動平均の傾きを求める。
   // 移動平均の計算対象は直近5本。つまり、MAの平均期間=5
   m_st_vOrderIndex.MA_Slope5 = DOUBLE_VALUE_MIN;
   mDataNum = 0;
   double buf_iMA = 0.0;
   ArrayInitialize(do_calc_Indexes_mData, 0.0);

   for(i = 0; i <  5; i++)  {
      buf_iMA  = iMA(
                    mSymbol,// 通貨ペア
                    mTimeframe_calc,   // 時間軸
                    5,            // MAの平均期間
                    0,            // MAシフト
                    MODE_SMA,     // MAの平均化メソッド
                    PRICE_CLOSE,  // 適用価格
                    mCalcShift +i // シフト
                 );

      if(buf_iMA > 0.0)  {
         do_calc_Indexes_mData[i] = NormalizeDouble(buf_iMA, global_Digits);
         mDataNum++;
      }
   }

   // iMAを2件以上取得できたときに傾きを計算する。
   if(mDataNum >= 2 ) {
      flag = false;
      flag = calcRegressionLine(do_calc_Indexes_mData, mDataNum, mSlope, mIntercept);
      // calcRegressionLineで求める傾きは、x軸がシフトの場合は反転させる必要がある。
      if(flag == true)  {
         mSlope = mSlope * (-1);
         m_st_vOrderIndex.MA_Slope5 = NormalizeDouble(mSlope, global_Digits) / global_Points;
         // 一つでも項目の計算に成功したら、trueとする。
         retFlag = true;         
      }
   }

   // シフト25本分の移動平均の傾きを求める。
   // 移動平均の計算対象は直近5本。
   mDataNum = 0;
   ArrayInitialize(do_calc_Indexes_mData, 0.0);

   m_st_vOrderIndex.MA_Slope25 = DOUBLE_VALUE_MIN;
   for(i = 0; i < 5; i++)  {
      buf_iMA = iMA(
                   global_Symbol,// 通貨ペア
                   mTimeframe_calc,   // 時間軸
                   25,           // MAの平均期間
                   0,            // MAシフト
                   MODE_SMA,     // MAの平均化メソッド
                   PRICE_CLOSE,  // 適用価格
                   mCalcShift +i // シフト
                );
      if(buf_iMA > 0.0)  {
         do_calc_Indexes_mData[i] = NormalizeDouble(buf_iMA, global_Digits);
         mDataNum++;
      }
   }
   // iMAを2件以上取得できたときに傾きを計算する。
   if(mDataNum >= 2)  {
      flag = false;
      flag = calcRegressionLine(do_calc_Indexes_mData, mDataNum, mSlope, mIntercept);
      // calcRegressionLineで求める傾きは、x軸がシフトの場合は反転させる必要がある。
      if(flag == true)  {
         mSlope = mSlope * (-1);
         m_st_vOrderIndex.MA_Slope25 = NormalizeDouble(mSlope, global_Digits)  / global_Points;
         // 一つでも項目の計算に成功したら、trueとする。
         retFlag = true;         
      }
   }

   // シフト75本分の移動平均の傾きを求める。
   // 移動平均の計算対象は直近5本。
   mDataNum = 0;
   m_st_vOrderIndex.MA_Slope75 = DOUBLE_VALUE_MIN;
   ArrayInitialize(do_calc_Indexes_mData, 0.0);

   for(i = 0; i < 5; i++)  {
      buf_iMA = iMA(
                   global_Symbol,// 通貨ペア
                   mTimeframe_calc,   // 時間軸
                   75,           // MAの平均期間
                   0,            // MAシフト
                   MODE_SMA,     // MAの平均化メソッド
                   PRICE_CLOSE,  // 適用価格
                   mCalcShift +i // シフト
                );
      if(buf_iMA > 0.0)  {
         do_calc_Indexes_mData[i] = NormalizeDouble(buf_iMA, global_Digits);
         mDataNum++;
      }
   }
   // iMAを2件以上取得できたときに傾きを計算する。
   if(mDataNum >= 2)  {
      flag = false;
      flag = calcRegressionLine(do_calc_Indexes_mData, mDataNum, mSlope, mIntercept);
      // calcRegressionLineで求める傾きは、x軸がシフトの場合は反転させる必要がある。
      if(flag == true)  {
         mSlope = mSlope * (-1);
         m_st_vOrderIndex.MA_Slope75 = NormalizeDouble(mSlope, global_Digits)  / global_Points;
         // 一つでも項目の計算に成功したら、trueとする。
         retFlag = true;
      }
   }


   // 2 ボリンジャーバンドBB
   // mCalcShiftから25本のシフトを対象とした平均と標準偏差を計算する。
   // 移動平均の計算対象は直近5本。つまり、MAの平均期間は5。
   // 計算基準時間のclose値 = 平均 + n ×　偏差を満たすnを計算する。
   m_st_vOrderIndex.BB_Width = DOUBLE_VALUE_MIN;
   mDataNum=0;
   ArrayInitialize(do_calc_Indexes_mData, 0.0);
   for(i = 0; i < 25; i++)  {
      buf_iMA = iMA(
                   mSymbol,// 通貨ペア
                   mTimeframe_calc,   // 時間軸
                   5,            // MAの平均期間
                   0,            // MAシフト
                   MODE_SMA,     // MAの平均化メソッド
                   PRICE_CLOSE,  // 適用価格
                   mCalcShift +i // シフト
                );
      if(buf_iMA > 0.0)  {
      
         do_calc_Indexes_mData[i] = NormalizeDouble(buf_iMA, global_Digits);
         mDataNum++;
      }
   }
   if(mDataNum >= 20)  {  // 20220308本来は25件のデータが欲しいが、エラーが発生して利用できなくなるケースがおおくなることから、感覚的に80%の20件のデータがあれば平均と偏差を計算し、BB_Widthを計算することとした。
      double mMean = DOUBLE_VALUE_MIN;
      double mSigma = DOUBLE_VALUE_MIN;
      flag = false;
      flag = calcMeanAndSigma(do_calc_Indexes_mData, mDataNum, mMean, mSigma);
      if(flag == true && mSigma != 0.0 && mSigma > DOUBLE_VALUE_MIN)  {
         // 計算基準時間のclose = 平均 + n ×　偏差を満たすnを計算する。　→　n = (close - 平均）÷偏差
         m_st_vOrderIndex.BB_Width = (NormalizeDouble(bufClosePrice, global_Digits) - NormalizeDouble(mMean, global_Digits)) / mSigma;

         
         // 一つでも項目の計算に成功したら、trueとする。
         retFlag = true;
      }
      else if(flag == true)  {
      }
   }
   else   {
      printf("[%d]VTエラー BB_Width計算失敗データ件数>%d< mCalcShift=%d　基準時間=%s", __LINE__,mDataNum, mCalcShift, TimeToStr(mCalcTime));
   }

// 3 一目均衡表:IK
   int mICHIMOKU_Tenkan =  9; //転換線期間
   int mICHIMOKU_Kijun  = 26; //基準線期間
   int mICHIMOKU_Senko  = 52; //先行スパン期間
 /*  
https://min-fx.jp/market/main-technicals/ichimoku/
・転換線が基準線を上抜く：買いシグナル(ゴールデンクロス) / 転換線が基準線を下抜く：売りシグナル(デッドクロス)   
https://info.monex.co.jp/technical-analysis/indicators/004.html   
基準線が上向きの状態で、転換線が基準線の下から上へ抜ける（ゴールデンクロス）を「好転」といい買いシグナルとなり、
逆に基準線が下向きの状態で転換線が基準線の上から下へ抜ける（デッドクロス）を「逆転」といい、売りシグナルとなります。   


https://min-fx.jp/market/main-technicals/ichimoku/
先行スパンを用いて分析を行う際には、 先行スパン1と先行スパン2の間を塗りつぶしたゾーン「雲」と呼ばれる帯状のエリアとローソク足の位置関係に注目します。
・ローソク足が雲を上抜けする：買いシグナル(上昇サイン)
・ローソク足が雲を下抜けする：売りシグナル(下落サイン)   
https://info.monex.co.jp/technical-analysis/indicators/004.html    
先行スパン1と先行スパン2に挟まれたゾーンのことを「雲(抵抗帯)」と呼び、「雲」とローソク足との位置を見るだけで、相場の動向をチェックすることが可能です。
① ローソク足が雲の上方にあれば強い相場、下方にあれば弱い相場と判断します。
② ローソク足よりも雲が上にある場合　⇒　上値抵抗線
ローソク足よりも雲が下にある場合　⇒　下値抵抗線
③ ローソク足が雲を下から上に突破した場合は上昇サインとなり 「好転」、逆にローソク足が雲を上から下に突破した場合は下落サインとなり「逆転」。
   

https://min-fx.jp/market/main-technicals/ichimoku/
遅行スパンもローソク足との位置関係で売買シグナルとして活用することができます。
・遅行スパンがローソク足を上抜く：買いシグナル
・遅行スパンがローソク足を下抜く：売りグナル
https://info.monex.co.jp/technical-analysis/indicators/004.html    
遅行線がローソク足を上回った場合を「好転」（買いシグナル）、逆に下回った場合を「逆転」（売りシグナル）と判断します。


https://min-fx.jp/market/main-technicals/ichimoku/
三役好転とは次の3つの買いシグナルが揃っている状況を指します。
・転換線が基準線を上抜く
・遅行スパンがローソク足を上抜く
・ローソク足が雲を上抜く
https://info.monex.co.jp/technical-analysis/indicators/004.html    
三役好転（三役逆転）
下記3つの条件が揃うと、非常に強い買いシグナル（売りシグナル）になります。
● 転換線＞基準線（転換線＜基準線）
● ローソク足＞雲（ローソク足＜雲）
● 遅行線＞ローソク足（遅行線＜ローソク足）
   
   
 */  
   // 転換線
   double tenkan  = NormalizeDouble(iIchimoku(mSymbol, mTimeframe_calc, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_TENKANSEN, mCalcShift), global_Digits);
   // 基準線
   double kijun   = NormalizeDouble(iIchimoku(mSymbol, mTimeframe_calc, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_KIJUNSEN, mCalcShift), global_Digits);
   // 遅行線
   double chikou  = NormalizeDouble(iIchimoku(mSymbol, mTimeframe_calc, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_CHIKOUSPAN, mCalcShift), global_Digits);
   // 先行線
   double senkouA = NormalizeDouble(iIchimoku(mSymbol, mTimeframe_calc, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_SENKOUSPANA, mCalcShift), global_Digits);
   double senkouB = NormalizeDouble(iIchimoku(mSymbol, mTimeframe_calc, mICHIMOKU_Tenkan, mICHIMOKU_Kijun, mICHIMOKU_Senko, MODE_SENKOUSPANB, mCalcShift), global_Digits);


   m_st_vOrderIndex.IK_TEN = DOUBLE_VALUE_MIN;
   m_st_vOrderIndex.IK_CHI = DOUBLE_VALUE_MIN;
   m_st_vOrderIndex.IK_LEG = DOUBLE_VALUE_MIN;

   // 転換線が基準線を上抜く：買いシグナル(ゴールデンクロス) / 転換線が基準線を下抜く：売りシグナル(デッドクロス)   
   // 転換線が基準線を上抜けている時の距離（PIPS数）を正、下抜けている時の距離（PIPS数）を負とする。
   if(NormalizeDouble(tenkan, global_Digits) > 0.0
      && NormalizeDouble(kijun, global_Digits)  > 0.0) {
         m_st_vOrderIndex.IK_TEN = (NormalizeDouble(tenkan, global_Digits) - NormalizeDouble(kijun, global_Digits)) / global_Points;
         // 一つでも項目の計算に成功したら、trueとする。
         retFlag = true;
   }
   else {
      // m_st_vOrderIndex.IK_TENを更新しない。
   }

   // 遅行スパンもローソク足との位置関係で売買シグナルとして活用することができます。
   // ・遅行スパンがローソク足を上抜く：買いシグナル
   // ・遅行スパンがローソク足を下抜く：売りグナル
   // 遅行スパンがローソク足を上抜けている時の距離（PIPS数）を正、下抜けている時の距離（PIPS数）を負とする。
   if(chikou > 0.0 && bufClosePrice > 0.0)  {
      m_st_vOrderIndex.IK_CHI = (NormalizeDouble(chikou, global_Digits) - NormalizeDouble(bufClosePrice, global_Digits)) / global_Points;
      // 一つでも項目の計算に成功したら、trueとする。
      retFlag = true;
   }
   else  {
   }

   // 先行スパンを用いて分析を行う際には、 先行スパン1と先行スパン2の間を塗りつぶしたゾーン「雲」と呼ばれる帯状のエリアとローソク足の位置関係に注目します。
   // ・ローソク足が雲を上抜けする：買いシグナル(上昇サイン) 
   // ・ローソク足が雲を下抜けする：売りシグナル(下落サイン)  
   // ・ローソク足の終値が、雲を上抜けている時の近い方の先行スパンとの距離（PIPS数）を正、
   //   ローソク足の終値が、雲を下抜けている時の近い方の先行スパンとの距離（PIPS数）を負。
   // bufClosePriceが基準線を上抜けている時は、先行スパン1と先行スパン2のうち大きい方と転換線との距離（PIPS数）
   if(NormalizeDouble(bufClosePrice, global_Digits) >= NormalizeDouble(senkouA, global_Digits)
      && NormalizeDouble(bufClosePrice, global_Digits) >= NormalizeDouble(senkouB, global_Digits)
      && NormalizeDouble(senkouA, global_Digits) > 0.0
      && NormalizeDouble(senkouB, global_Digits) > 0.0)  {
      // senkouAの方が雲の上の場合
      if(NormalizeDouble(senkouA, global_Digits) >= NormalizeDouble(senkouB, global_Digits))  {
         m_st_vOrderIndex.IK_LEG = (NormalizeDouble(bufClosePrice, global_Digits) - NormalizeDouble(senkouA, global_Digits)) / global_Points;
         // 一つでも項目の計算に成功したら、trueとする。
         retFlag = true;
      }
      // senkouBの方が雲の上の場合
      else  {
         m_st_vOrderIndex.IK_LEG = (NormalizeDouble(bufClosePrice, global_Digits) - NormalizeDouble(senkouB, global_Digits)) / global_Points;
         // 一つでも項目の計算に成功したら、trueとする。
         retFlag = true;
      }
   }
   // bufClosePriceが基準線を下抜けている時は、先行スパン1と先行スパン2のうち小さい方と転換線との距離（PIPS数）
   if(NormalizeDouble(bufClosePrice, global_Digits) <= NormalizeDouble(senkouA, global_Digits)
      && NormalizeDouble(bufClosePrice, global_Digits) <= NormalizeDouble(senkouB, global_Digits)
      && NormalizeDouble(senkouA, global_Digits) > 0.0
      && NormalizeDouble(senkouB, global_Digits) > 0.0)  {
      // senkouAの方が雲の下の場合
      if(NormalizeDouble(senkouA, global_Digits) <= NormalizeDouble(senkouB, global_Digits))  {
         m_st_vOrderIndex.IK_LEG = (NormalizeDouble(bufClosePrice, global_Digits) - NormalizeDouble(senkouA, global_Digits)) / global_Points;
         // 一つでも項目の計算に成功したら、trueとする。
         retFlag = true;
      }
      else  {
         m_st_vOrderIndex.IK_LEG = (NormalizeDouble(bufClosePrice, global_Digits) - NormalizeDouble(senkouB, global_Digits)) / global_Points;
         // 一つでも項目の計算に成功したら、trueとする。
         retFlag = true;
      }
   }
   else  {
      // bufClosePriceが、先行スパン1と先行スパン2の間（雲）にあるため、距離無し。
   }


   // 4 MACD:MACD
   int mMACDGC = 0;
   int mMACDDC = 0;
   m_st_vOrderIndex.MACD_GC = INT_VALUE_MIN;
   m_st_vOrderIndex.MACD_DC = INT_VALUE_MIN;

   flag = false;
   flag = getLastMACD_Cross(mTimeframe_calc, mCalcShift, mMACDGC, mMACDDC) ;
   if(flag == true)  {
      m_st_vOrderIndex.MACD_GC = mMACDGC;
      m_st_vOrderIndex.MACD_DC = mMACDDC;
      // 一つでも項目の計算に成功したら、trueとする。
      retFlag = true;
      
   }


   //
   // オシレーター分析
   // 1 RSI:RSI
   m_st_vOrderIndex.RSI_VAL = NormalizeDouble(
         iRSI(
            global_Symbol,// 通貨ペア
            mTimeframe_calc,   // 時間軸
            14,           // 平均期間
            PRICE_CLOSE,  // 適用価格
            mCalcShift    // シフト
         ), global_Digits);

   // 2 ストキャスティクス:STOC
   m_st_vOrderIndex.STOC_VAL = NormalizeDouble(
         iStochastic(
            global_Symbol,// 通貨ペア
            mTimeframe_calc,   // 時間軸
            5,            // %K期間
            3,            // %D期間
            3,            // スローイング
            MODE_SMA,     // 平均化メソッド
            0,            // 価格(Low/HighまたはClose/Close)
            MODE_MAIN,    // ラインインデックス
            mCalcShift    // シフト
         ), global_Digits);
   if(m_st_vOrderIndex.STOC_VAL > 0.0) {
      // 一つでも項目の計算に成功したら、trueとする。
      retFlag = true;
   }
            
   int mSTOCGC = 0;
   int mSTOCDC = 0;
   flag = false;
   m_st_vOrderIndex.STOC_GC = INT_VALUE_MIN;
   m_st_vOrderIndex.STOC_DC = INT_VALUE_MIN;

   flag = getLastSTOC_Cross(mTimeframe_calc, mCalcShift, mSTOCGC, mSTOCDC) ;
   if(flag == true)  {
      m_st_vOrderIndex.STOC_GC = mSTOCGC;
      m_st_vOrderIndex.STOC_DC = mSTOCDC;
      // 一つでも項目の計算に成功したら、trueとする。
      retFlag = true;
   }

   // 3 酒田五法（ローソク足の組み合わせのため、除外）
   //4 RCI:RCI・-100%～100%の間で推移する数値。予想は、買いで利益が出るのは-80％付近。売りで利益が出るのは+80％付近。:VAL
   // 短期線[9] :主にエントリーに使用
   // 中期線[26]:主にトレンド判断用。
   // 長期線[52]:主に上位足のトレンド確認用。
   m_st_vOrderIndex.RCI_VAL = NormalizeDouble(mRCI2(global_Symbol, mTimeframe_calc, 26, mCalcShift), global_Digits);

   if(MathAbs(m_st_vOrderIndex.RCI_VAL) <= 100) {
      // 一つでも項目の計算に成功したら、trueとする。
      retFlag = true;
   }
   
   if(retFlag == false) {
      return false;
   }
   else {
      m_st_vOrderIndex.symbol     = mSymbol;
      m_st_vOrderIndex.timeframe  = mTimeframe_calc;
      m_st_vOrderIndex.calcTime   = mCalcTime;
   }

   return true;
}

//+------------------------------------------------------------------+
//|  vAnalizedIndexをファイル出力する                                |
//+------------------------------------------------------------------+
void write_st_vAnalizedIndexes(string mFilename) {
   if(VT_FILEIO_FLAG == false) {
      return ;
   }
   int fileHandle1 = FileOpen("MeanSigma_BUYPROFIT" + mFilename, FILE_WRITE | FILE_CSV,",");
   if(st_vAnalyzedIndexesBUY_Profit.analyzeTime <= 0) {
      FileWrite(fileHandle1,"ファイル出力データ無し");
   }
   else {
      FileWrite(fileHandle1,"strategyID",st_vAnalyzedIndexesBUY_Profit.strategyID);
      FileWrite(fileHandle1,"symbol",st_vAnalyzedIndexesBUY_Profit.symbol);
      FileWrite(fileHandle1,"timeframe",st_vAnalyzedIndexesBUY_Profit.timeframe);
      FileWrite(fileHandle1,"orderType",st_vAnalyzedIndexesBUY_Profit.orderType);
      FileWrite(fileHandle1,"PLFlag",st_vAnalyzedIndexesBUY_Profit.PLFlag);
      FileWrite(fileHandle1,"analyzeTime",TimeToStr(st_vAnalyzedIndexesBUY_Profit.analyzeTime));
      FileWrite(fileHandle1,"MA_GC_MEAN",st_vAnalyzedIndexesBUY_Profit.MA_GC_MEAN);
      FileWrite(fileHandle1,"MA_GC_SIGMA",st_vAnalyzedIndexesBUY_Profit.MA_GC_SIGMA);
      FileWrite(fileHandle1,"MA_DC_MEAN",st_vAnalyzedIndexesBUY_Profit.MA_DC_MEAN);
      FileWrite(fileHandle1,"MA_DC_SIGMA",st_vAnalyzedIndexesBUY_Profit.MA_DC_SIGMA);
      FileWrite(fileHandle1,"MA_Slope5_MEAN",st_vAnalyzedIndexesBUY_Profit.MA_Slope5_MEAN);
      FileWrite(fileHandle1,"MA_Slope5_SIGMA",st_vAnalyzedIndexesBUY_Profit.MA_Slope5_SIGMA);
      FileWrite(fileHandle1,"MA_Slope25_MEAN",st_vAnalyzedIndexesBUY_Profit.MA_Slope25_MEAN);
      FileWrite(fileHandle1,"MA_Slope25_SIGMA",st_vAnalyzedIndexesBUY_Profit.MA_Slope25_SIGMA);
      FileWrite(fileHandle1,"MA_Slope75_MEAN",st_vAnalyzedIndexesBUY_Profit.MA_Slope75_MEAN);
      FileWrite(fileHandle1,"MA_Slope75_SIGMA",st_vAnalyzedIndexesBUY_Profit.MA_Slope75_SIGMA);
      FileWrite(fileHandle1,"BB_Width_MEAN",st_vAnalyzedIndexesBUY_Profit.BB_Width_MEAN);
      FileWrite(fileHandle1,"BB_Width_SIGMA",st_vAnalyzedIndexesBUY_Profit.BB_Width_SIGMA);
      FileWrite(fileHandle1,"IK_TEN_MEAN",st_vAnalyzedIndexesBUY_Profit.IK_TEN_MEAN);
      FileWrite(fileHandle1,"IK_TEN_SIGMA",st_vAnalyzedIndexesBUY_Profit.IK_TEN_SIGMA);
      FileWrite(fileHandle1,"IK_CHI_MEAN",st_vAnalyzedIndexesBUY_Profit.IK_CHI_MEAN);
      FileWrite(fileHandle1,"IK_CHI_SIGMA",st_vAnalyzedIndexesBUY_Profit.IK_CHI_SIGMA);
      FileWrite(fileHandle1,"IK_LEG_MEAN",st_vAnalyzedIndexesBUY_Profit.IK_LEG_MEAN);
      FileWrite(fileHandle1,"IK_LEG_SIGMA",st_vAnalyzedIndexesBUY_Profit.IK_LEG_SIGMA);
      FileWrite(fileHandle1,"MACD_GC_MEAN",st_vAnalyzedIndexesBUY_Profit.MACD_GC_MEAN);
      FileWrite(fileHandle1,"MACD_GC_SIGMA",st_vAnalyzedIndexesBUY_Profit.MACD_GC_SIGMA);
      FileWrite(fileHandle1,"MACD_DC_MEAN",st_vAnalyzedIndexesBUY_Profit.MACD_DC_MEAN);
      FileWrite(fileHandle1,"MACD_DC_SIGMA",st_vAnalyzedIndexesBUY_Profit.MACD_DC_SIGMA);
      FileWrite(fileHandle1,"RSI_VAL_MEAN",st_vAnalyzedIndexesBUY_Profit.RSI_VAL_MEAN);
      FileWrite(fileHandle1,"RSI_VAL_SIGMA",st_vAnalyzedIndexesBUY_Profit.RSI_VAL_SIGMA);
      FileWrite(fileHandle1,"STOC_VAL_MEAN",st_vAnalyzedIndexesBUY_Profit.STOC_VAL_MEAN);
      FileWrite(fileHandle1,"STOC_VAL_SIGMA",st_vAnalyzedIndexesBUY_Profit.STOC_VAL_SIGMA);
      FileWrite(fileHandle1,"STOC_GC_MEAN",st_vAnalyzedIndexesBUY_Profit.STOC_GC_MEAN);
      FileWrite(fileHandle1,"STOC_GC_SIGMA",st_vAnalyzedIndexesBUY_Profit.STOC_GC_SIGMA);
      FileWrite(fileHandle1,"STOC_DC_MEAN",st_vAnalyzedIndexesBUY_Profit.STOC_DC_MEAN);
      FileWrite(fileHandle1,"STOC_DC_SIGMA",st_vAnalyzedIndexesBUY_Profit.STOC_DC_SIGMA);
      FileWrite(fileHandle1,"RCI_VAL_MEAN",st_vAnalyzedIndexesBUY_Profit.RCI_VAL_MEAN);
      FileWrite(fileHandle1,"RCI_VAL_SIGMA",st_vAnalyzedIndexesBUY_Profit.RCI_VAL_SIGMA);
   }
   FileClose(fileHandle1);

   fileHandle1 = FileOpen("MeanSigma_BUYLOSS" + mFilename, FILE_WRITE | FILE_CSV,",");

   if(st_vAnalyzedIndexesBUY_Loss.analyzeTime <= 0) {
      FileWrite(fileHandle1,"ファイル出力データ無し");
   }
   else {
      FileWrite(fileHandle1,"strategyID",st_vAnalyzedIndexesBUY_Loss.strategyID);
      FileWrite(fileHandle1,"symbol",st_vAnalyzedIndexesBUY_Loss.symbol);
      FileWrite(fileHandle1,"timeframe",st_vAnalyzedIndexesBUY_Loss.timeframe);
      FileWrite(fileHandle1,"orderType",st_vAnalyzedIndexesBUY_Loss.orderType);
      FileWrite(fileHandle1,"PLFlag",st_vAnalyzedIndexesBUY_Loss.PLFlag);
      FileWrite(fileHandle1,"analyzeTime",TimeToStr(st_vAnalyzedIndexesBUY_Profit.analyzeTime));
      FileWrite(fileHandle1,"MA_GC_MEAN",st_vAnalyzedIndexesBUY_Loss.MA_GC_MEAN);
      FileWrite(fileHandle1,"MA_GC_SIGMA",st_vAnalyzedIndexesBUY_Loss.MA_GC_SIGMA);
      FileWrite(fileHandle1,"MA_DC_MEAN",st_vAnalyzedIndexesBUY_Loss.MA_DC_MEAN);
      FileWrite(fileHandle1,"MA_DC_SIGMA",st_vAnalyzedIndexesBUY_Loss.MA_DC_SIGMA);
      FileWrite(fileHandle1,"MA_Slope5_MEAN",st_vAnalyzedIndexesBUY_Loss.MA_Slope5_MEAN);
      FileWrite(fileHandle1,"MA_Slope5_SIGMA",st_vAnalyzedIndexesBUY_Loss.MA_Slope5_SIGMA);
      FileWrite(fileHandle1,"MA_Slope25_MEAN",st_vAnalyzedIndexesBUY_Loss.MA_Slope25_MEAN);
      FileWrite(fileHandle1,"MA_Slope25_SIGMA",st_vAnalyzedIndexesBUY_Loss.MA_Slope25_SIGMA);
      FileWrite(fileHandle1,"MA_Slope75_MEAN",st_vAnalyzedIndexesBUY_Loss.MA_Slope75_MEAN);
      FileWrite(fileHandle1,"MA_Slope75_SIGMA",st_vAnalyzedIndexesBUY_Loss.MA_Slope75_SIGMA);
      FileWrite(fileHandle1,"BB_Width_MEAN",st_vAnalyzedIndexesBUY_Loss.BB_Width_MEAN);
      FileWrite(fileHandle1,"BB_Width_SIGMA",st_vAnalyzedIndexesBUY_Loss.BB_Width_SIGMA);
      FileWrite(fileHandle1,"IK_TEN_MEAN",st_vAnalyzedIndexesBUY_Loss.IK_TEN_MEAN);
      FileWrite(fileHandle1,"IK_TEN_SIGMA",st_vAnalyzedIndexesBUY_Loss.IK_TEN_SIGMA);
      FileWrite(fileHandle1,"IK_CHI_MEAN",st_vAnalyzedIndexesBUY_Loss.IK_CHI_MEAN);
      FileWrite(fileHandle1,"IK_CHI_SIGMA",st_vAnalyzedIndexesBUY_Loss.IK_CHI_SIGMA);
      FileWrite(fileHandle1,"IK_LEG_MEAN",st_vAnalyzedIndexesBUY_Loss.IK_LEG_MEAN);
      FileWrite(fileHandle1,"IK_LEG_SIGMA",st_vAnalyzedIndexesBUY_Loss.IK_LEG_SIGMA);
      FileWrite(fileHandle1,"MACD_GC_MEAN",st_vAnalyzedIndexesBUY_Loss.MACD_GC_MEAN);
      FileWrite(fileHandle1,"MACD_GC_SIGMA",st_vAnalyzedIndexesBUY_Loss.MACD_GC_SIGMA);
      FileWrite(fileHandle1,"MACD_DC_MEAN",st_vAnalyzedIndexesBUY_Loss.MACD_DC_MEAN);
      FileWrite(fileHandle1,"MACD_DC_SIGMA",st_vAnalyzedIndexesBUY_Loss.MACD_DC_SIGMA);
      FileWrite(fileHandle1,"RSI_VAL_MEAN",st_vAnalyzedIndexesBUY_Loss.RSI_VAL_MEAN);
      FileWrite(fileHandle1,"RSI_VAL_SIGMA",st_vAnalyzedIndexesBUY_Loss.RSI_VAL_SIGMA);
      FileWrite(fileHandle1,"STOC_VAL_MEAN",st_vAnalyzedIndexesBUY_Loss.STOC_VAL_MEAN);
      FileWrite(fileHandle1,"STOC_VAL_SIGMA",st_vAnalyzedIndexesBUY_Loss.STOC_VAL_SIGMA);
      FileWrite(fileHandle1,"STOC_GC_MEAN",st_vAnalyzedIndexesBUY_Loss.STOC_GC_MEAN);
      FileWrite(fileHandle1,"STOC_GC_SIGMA",st_vAnalyzedIndexesBUY_Loss.STOC_GC_SIGMA);
      FileWrite(fileHandle1,"STOC_DC_MEAN",st_vAnalyzedIndexesBUY_Loss.STOC_DC_MEAN);
      FileWrite(fileHandle1,"STOC_DC_SIGMA",st_vAnalyzedIndexesBUY_Loss.STOC_DC_SIGMA);
      FileWrite(fileHandle1,"RCI_VAL_MEAN",st_vAnalyzedIndexesBUY_Loss.RCI_VAL_MEAN);
      FileWrite(fileHandle1,"RCI_VAL_SIGMA",st_vAnalyzedIndexesBUY_Loss.RCI_VAL_SIGMA);
   }
   FileClose(fileHandle1);
   fileHandle1 = FileOpen("MeanSigma_SELLLOSS" + mFilename, FILE_WRITE | FILE_CSV,",");


   if(st_vAnalyzedIndexesSELL_Loss.analyzeTime <= 0) {
      FileWrite(fileHandle1,"ファイル出力データ無し");
   }
   else {
      FileWrite(fileHandle1,"strategyID",st_vAnalyzedIndexesSELL_Loss.strategyID);
      FileWrite(fileHandle1,"symbol",st_vAnalyzedIndexesSELL_Loss.symbol);
      FileWrite(fileHandle1,"timeframe",st_vAnalyzedIndexesSELL_Loss.timeframe);
      FileWrite(fileHandle1,"orderType",st_vAnalyzedIndexesSELL_Loss.orderType);
      FileWrite(fileHandle1,"PLFlag",st_vAnalyzedIndexesSELL_Loss.PLFlag);
      FileWrite(fileHandle1,"analyzeTime",TimeToStr(st_vAnalyzedIndexesBUY_Profit.analyzeTime));
      FileWrite(fileHandle1,"MA_GC_MEAN",st_vAnalyzedIndexesSELL_Loss.MA_GC_MEAN);
      FileWrite(fileHandle1,"MA_GC_SIGMA",st_vAnalyzedIndexesSELL_Loss.MA_GC_SIGMA);
      FileWrite(fileHandle1,"MA_DC_MEAN",st_vAnalyzedIndexesSELL_Loss.MA_DC_MEAN);
      FileWrite(fileHandle1,"MA_DC_SIGMA",st_vAnalyzedIndexesSELL_Loss.MA_DC_SIGMA);
      FileWrite(fileHandle1,"MA_Slope5_MEAN",st_vAnalyzedIndexesSELL_Loss.MA_Slope5_MEAN);
      FileWrite(fileHandle1,"MA_Slope5_SIGMA",st_vAnalyzedIndexesSELL_Loss.MA_Slope5_SIGMA);
      FileWrite(fileHandle1,"MA_Slope25_MEAN",st_vAnalyzedIndexesSELL_Loss.MA_Slope25_MEAN);
      FileWrite(fileHandle1,"MA_Slope25_SIGMA",st_vAnalyzedIndexesSELL_Loss.MA_Slope25_SIGMA);
      FileWrite(fileHandle1,"MA_Slope75_MEAN",st_vAnalyzedIndexesSELL_Loss.MA_Slope75_MEAN);
      FileWrite(fileHandle1,"MA_Slope75_SIGMA",st_vAnalyzedIndexesSELL_Loss.MA_Slope75_SIGMA);
      FileWrite(fileHandle1,"BB_Width_MEAN",st_vAnalyzedIndexesSELL_Loss.BB_Width_MEAN);
      FileWrite(fileHandle1,"BB_Width_SIGMA",st_vAnalyzedIndexesSELL_Loss.BB_Width_SIGMA);
      FileWrite(fileHandle1,"IK_TEN_MEAN",st_vAnalyzedIndexesSELL_Loss.IK_TEN_MEAN);
      FileWrite(fileHandle1,"IK_TEN_SIGMA",st_vAnalyzedIndexesSELL_Loss.IK_TEN_SIGMA);
      FileWrite(fileHandle1,"IK_CHI_MEAN",st_vAnalyzedIndexesSELL_Loss.IK_CHI_MEAN);
      FileWrite(fileHandle1,"IK_CHI_SIGMA",st_vAnalyzedIndexesSELL_Loss.IK_CHI_SIGMA);
      FileWrite(fileHandle1,"IK_LEG_MEAN",st_vAnalyzedIndexesSELL_Loss.IK_LEG_MEAN);
      FileWrite(fileHandle1,"IK_LEG_SIGMA",st_vAnalyzedIndexesSELL_Loss.IK_LEG_SIGMA);
      FileWrite(fileHandle1,"MACD_GC_MEAN",st_vAnalyzedIndexesSELL_Loss.MACD_GC_MEAN);
      FileWrite(fileHandle1,"MACD_GC_SIGMA",st_vAnalyzedIndexesSELL_Loss.MACD_GC_SIGMA);
      FileWrite(fileHandle1,"MACD_DC_MEAN",st_vAnalyzedIndexesSELL_Loss.MACD_DC_MEAN);
      FileWrite(fileHandle1,"MACD_DC_SIGMA",st_vAnalyzedIndexesSELL_Loss.MACD_DC_SIGMA);
      FileWrite(fileHandle1,"RSI_VAL_MEAN",st_vAnalyzedIndexesSELL_Loss.RSI_VAL_MEAN);
      FileWrite(fileHandle1,"RSI_VAL_SIGMA",st_vAnalyzedIndexesSELL_Loss.RSI_VAL_SIGMA);
      FileWrite(fileHandle1,"STOC_VAL_MEAN",st_vAnalyzedIndexesSELL_Loss.STOC_VAL_MEAN);
      FileWrite(fileHandle1,"STOC_VAL_SIGMA",st_vAnalyzedIndexesSELL_Loss.STOC_VAL_SIGMA);
      FileWrite(fileHandle1,"STOC_GC_MEAN",st_vAnalyzedIndexesSELL_Loss.STOC_GC_MEAN);
      FileWrite(fileHandle1,"STOC_GC_SIGMA",st_vAnalyzedIndexesSELL_Loss.STOC_GC_SIGMA);
      FileWrite(fileHandle1,"STOC_DC_MEAN",st_vAnalyzedIndexesSELL_Loss.STOC_DC_MEAN);
      FileWrite(fileHandle1,"STOC_DC_SIGMA",st_vAnalyzedIndexesSELL_Loss.STOC_DC_SIGMA);
      FileWrite(fileHandle1,"RCI_VAL_MEAN",st_vAnalyzedIndexesSELL_Loss.RCI_VAL_MEAN);
      FileWrite(fileHandle1,"RCI_VAL_SIGMA",st_vAnalyzedIndexesSELL_Loss.RCI_VAL_SIGMA);
   }
   
   FileClose(fileHandle1);

   fileHandle1 = FileOpen("MeanSigma_SELLPROFIT" + mFilename, FILE_WRITE | FILE_CSV,",");
   if(st_vAnalyzedIndexesSELL_Profit.analyzeTime <= 0) {
      FileWrite(fileHandle1,"ファイル出力データ無し");
   }
   else {
      FileWrite(fileHandle1,"strategyID",st_vAnalyzedIndexesSELL_Profit.strategyID);
      FileWrite(fileHandle1,"symbol",st_vAnalyzedIndexesSELL_Profit.symbol);
      FileWrite(fileHandle1,"timeframe",st_vAnalyzedIndexesSELL_Profit.timeframe);
      FileWrite(fileHandle1,"orderType",st_vAnalyzedIndexesSELL_Profit.orderType);
      FileWrite(fileHandle1,"PLFlag",st_vAnalyzedIndexesSELL_Profit.PLFlag);
      FileWrite(fileHandle1,"analyzeTime",TimeToStr(st_vAnalyzedIndexesBUY_Profit.analyzeTime));
      FileWrite(fileHandle1,"MA_GC_MEAN",st_vAnalyzedIndexesSELL_Profit.MA_GC_MEAN);
      FileWrite(fileHandle1,"MA_GC_SIGMA",st_vAnalyzedIndexesSELL_Profit.MA_GC_SIGMA);
      FileWrite(fileHandle1,"MA_DC_MEAN",st_vAnalyzedIndexesSELL_Profit.MA_DC_MEAN);
      FileWrite(fileHandle1,"MA_DC_SIGMA",st_vAnalyzedIndexesSELL_Profit.MA_DC_SIGMA);
      FileWrite(fileHandle1,"MA_Slope5_MEAN",st_vAnalyzedIndexesSELL_Profit.MA_Slope5_MEAN);
      FileWrite(fileHandle1,"MA_Slope5_SIGMA",st_vAnalyzedIndexesSELL_Profit.MA_Slope5_SIGMA);
      FileWrite(fileHandle1,"MA_Slope25_MEAN",st_vAnalyzedIndexesSELL_Profit.MA_Slope25_MEAN);
      FileWrite(fileHandle1,"MA_Slope25_SIGMA",st_vAnalyzedIndexesSELL_Profit.MA_Slope25_SIGMA);
      FileWrite(fileHandle1,"MA_Slope75_MEAN",st_vAnalyzedIndexesSELL_Profit.MA_Slope75_MEAN);
      FileWrite(fileHandle1,"MA_Slope75_SIGMA",st_vAnalyzedIndexesSELL_Profit.MA_Slope75_SIGMA);
      FileWrite(fileHandle1,"BB_Width_MEAN",st_vAnalyzedIndexesSELL_Profit.BB_Width_MEAN);
      FileWrite(fileHandle1,"BB_Width_SIGMA",st_vAnalyzedIndexesSELL_Profit.BB_Width_SIGMA);
      FileWrite(fileHandle1,"IK_TEN_MEAN",st_vAnalyzedIndexesSELL_Profit.IK_TEN_MEAN);
      FileWrite(fileHandle1,"IK_TEN_SIGMA",st_vAnalyzedIndexesSELL_Profit.IK_TEN_SIGMA);
      FileWrite(fileHandle1,"IK_CHI_MEAN",st_vAnalyzedIndexesSELL_Profit.IK_CHI_MEAN);
      FileWrite(fileHandle1,"IK_CHI_SIGMA",st_vAnalyzedIndexesSELL_Profit.IK_CHI_SIGMA);
      FileWrite(fileHandle1,"IK_LEG_MEAN",st_vAnalyzedIndexesSELL_Profit.IK_LEG_MEAN);
      FileWrite(fileHandle1,"IK_LEG_SIGMA",st_vAnalyzedIndexesSELL_Profit.IK_LEG_SIGMA);
      FileWrite(fileHandle1,"MACD_GC_MEAN",st_vAnalyzedIndexesSELL_Profit.MACD_GC_MEAN);
      FileWrite(fileHandle1,"MACD_GC_SIGMA",st_vAnalyzedIndexesSELL_Profit.MACD_GC_SIGMA);
      FileWrite(fileHandle1,"MACD_DC_MEAN",st_vAnalyzedIndexesSELL_Profit.MACD_DC_MEAN);
      FileWrite(fileHandle1,"MACD_DC_SIGMA",st_vAnalyzedIndexesSELL_Profit.MACD_DC_SIGMA);
      FileWrite(fileHandle1,"RSI_VAL_MEAN",st_vAnalyzedIndexesSELL_Profit.RSI_VAL_MEAN);
      FileWrite(fileHandle1,"RSI_VAL_SIGMA",st_vAnalyzedIndexesSELL_Profit.RSI_VAL_SIGMA);
      FileWrite(fileHandle1,"STOC_VAL_MEAN",st_vAnalyzedIndexesSELL_Profit.STOC_VAL_MEAN);
      FileWrite(fileHandle1,"STOC_VAL_SIGMA",st_vAnalyzedIndexesSELL_Profit.STOC_VAL_SIGMA);
      FileWrite(fileHandle1,"STOC_GC_MEAN",st_vAnalyzedIndexesSELL_Profit.STOC_GC_MEAN);
      FileWrite(fileHandle1,"STOC_GC_SIGMA",st_vAnalyzedIndexesSELL_Profit.STOC_GC_SIGMA);
      FileWrite(fileHandle1,"STOC_DC_MEAN",st_vAnalyzedIndexesSELL_Profit.STOC_DC_MEAN);
      FileWrite(fileHandle1,"STOC_DC_SIGMA",st_vAnalyzedIndexesSELL_Profit.STOC_DC_SIGMA);
      FileWrite(fileHandle1,"RCI_VAL_MEAN",st_vAnalyzedIndexesSELL_Profit.RCI_VAL_MEAN);
      FileWrite(fileHandle1,"RCI_VAL_SIGMA",st_vAnalyzedIndexesSELL_Profit.RCI_VAL_SIGMA);
   }
   FileClose(fileHandle1);


  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void read_st_vAnalyzedIndexes() {
   int fileHandle1;
   fileHandle1    = FileOpen("MeanSigma_BUYPROFIT.csv", FILE_READ | FILE_CSV,",");
   if(fileHandle1 < 0) {
      return ;
   }

   string bufRead1;
   string bufRead2;

   while(true) {
      if(FileIsEnding(fileHandle1) == true) {
         break;
      }
      bufRead1 = FileReadString(fileHandle1);
      if(FileIsEnding(fileHandle1) == true) {
         break;
      }
      if(FileIsLineEnding(fileHandle1) == true) {
         break;
      }
      bufRead2 = FileReadString(fileHandle1);
      printf("[%d]VT ファイル読み込み　bu1=%s buf2=%s", __LINE__, bufRead1, bufRead2);

      if(FileIsLineEnding(fileHandle1) == true)  {
         printf("[%d]VT ファイル読み込み　bu1=%s buf2=%s", __LINE__, bufRead1, bufRead2);
         if(StringCompare(bufRead1, "strategyID") == 0) {
            st_vAnalyzedIndexesBUY_Profit.strategyID = bufRead2;
         }
         if(StringCompare(bufRead1, "symbol") == 0) {
            st_vAnalyzedIndexesBUY_Profit.symbol = bufRead2;
         }
         if(StringCompare(bufRead1, "timeframe") == 0)  {
            st_vAnalyzedIndexesBUY_Profit.timeframe = (int)StringToInteger(bufRead2);
         }
         if(StringCompare(bufRead1, "orderType") == 0) {
            st_vAnalyzedIndexesBUY_Profit.orderType = (int)StringToInteger(bufRead2);
         }
         if(StringCompare(bufRead1, "PLFlag") == 0) {
            st_vAnalyzedIndexesBUY_Profit.PLFlag = (int)StringToInteger(bufRead2);
         }
         if(StringCompare(bufRead1, "analyzeTime") == 0) {
            st_vAnalyzedIndexesBUY_Profit.analyzeTime = (datetime)StringToInteger(bufRead2);
         }
         if(StringCompare(bufRead1, "MA_GC_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.MA_GC_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MA_GC_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.MA_GC_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MA_DC_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.MA_DC_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MA_DC_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.MA_DC_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MA_Slope5_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.MA_Slope5_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MA_Slope5_SIGMA") == 0)  {
            st_vAnalyzedIndexesBUY_Profit.MA_Slope5_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MA_Slope25_MEAN") == 0)  {
            st_vAnalyzedIndexesBUY_Profit.MA_Slope25_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MA_Slope25_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.MA_Slope25_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MA_Slope75_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.MA_Slope75_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MA_Slope75_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.MA_Slope75_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "BB_Width_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.BB_Width_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "BB_Width_SIGMA") == 0)  {
            st_vAnalyzedIndexesBUY_Profit.BB_Width_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "IK_TEN_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.IK_TEN_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "IK_TEN_SIGMA") == 0){
            st_vAnalyzedIndexesBUY_Profit.IK_TEN_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "IK_CHI_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.IK_CHI_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "IK_CHI_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.IK_CHI_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "IK_LEG_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.IK_LEG_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "IK_LEG_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.IK_LEG_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MACD_GC_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.MACD_GC_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MACD_GC_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.MACD_GC_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MACD_DC_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.MACD_DC_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "MACD_DC_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.MACD_DC_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "RSI_VAL_MEAN") == 0)  {
            st_vAnalyzedIndexesBUY_Profit.RSI_VAL_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "RSI_VAL_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.RSI_VAL_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "STOC_VAL_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.STOC_VAL_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "STOC_VAL_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.STOC_VAL_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "STOC_GC_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.STOC_GC_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "STOC_GC_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.STOC_GC_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "STOC_DC_MEAN") == 0) {
            st_vAnalyzedIndexesBUY_Profit.STOC_DC_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "STOC_DC_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.STOC_DC_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "RCI_VAL_MEAN") == 0)  {
            st_vAnalyzedIndexesBUY_Profit.RCI_VAL_MEAN = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
         if(StringCompare(bufRead1, "RCI_VAL_SIGMA") == 0) {
            st_vAnalyzedIndexesBUY_Profit.RCI_VAL_SIGMA = NormalizeDouble(StringToDouble(bufRead2), global_Digits);
         }
      }
   }
}



// 各指標が、一般的に言われている条件を満たしていれば、trueを返す。
// 条件に原則1点の点数付けをし、平均点がGENERALRULE_PER(仮置きとして全体の4分の3＝75%)以上であれば、条件を満たしていると判断する。
// ただし、指標がDOUBLE_VALUE_MINかINT_VALUE_MINの場合は条件を満たすかどうかの判断をしない。
// 判断した個数satisfyPointALL=0の時は、何も判断できないため、falseを返す。
bool satisfyGeneralRules(st_vOrderIndex &curr_st_vOrderIndexes, int mBuySellProfitLoss) {
   int satisfyPoint = 0;    // 判定したもののうち、条件を満たした項目数
   int satisfyPointALL = 0; // 判定した総数

   if(mBuySellProfitLoss == vBUY_PROFIT
      || mBuySellProfitLoss == vSELL_LOSS) {
      //
      // 買い＆利益、売り＆損失
      //
      // 1 移動平均:MA
      // ①ゴールデンクロスがデッドクロスより近い
      if(curr_st_vOrderIndexes.MA_GC > INT_VALUE_MIN 
          && curr_st_vOrderIndexes.MA_DC > INT_VALUE_MIN ) {
         if(curr_st_vOrderIndexes.MA_GC < curr_st_vOrderIndexes.MA_DC) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      
      // ②傾きが正

      if(curr_st_vOrderIndexes.MA_Slope5 > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.MA_Slope5 > 0.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      if(curr_st_vOrderIndexes.MA_Slope25 > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.MA_Slope25 > 0.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      if(curr_st_vOrderIndexes.MA_Slope75 > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.MA_Slope75 > 0.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      
      // 2 ボリンジャーバンドBB
      // ①nが1以上
      
      if(curr_st_vOrderIndexes.BB_Width > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.BB_Width > 1.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      
      // 3 一目均衡表:IK
      // ①IK_TENが正
      if(curr_st_vOrderIndexes.IK_TEN > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.IK_TEN > 0.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      
      // ②IK_CHIが正
      if(curr_st_vOrderIndexes.IK_CHI > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.IK_CHI > 0.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      
      // ③IK_LEGが正
      if(curr_st_vOrderIndexes.IK_LEG > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.IK_LEG > 0.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      
      // 4 MACD:MACD
      // ①ゴールデンクロスがデッドクロスより近い
      
      if(curr_st_vOrderIndexes.MACD_GC > INT_VALUE_MIN 
          && curr_st_vOrderIndexes.MACD_DC > INT_VALUE_MIN ) {
         if(curr_st_vOrderIndexes.MACD_GC < curr_st_vOrderIndexes.MACD_DC) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      
      // 1 RSI:RSI
      // ①30.0以下。＝20％～30％を割り込むと売られ過ぎ
      
      if(curr_st_vOrderIndexes.RSI_VAL > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.RSI_VAL < 30.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      
      // 2 ストキャスティクス:STOC
      // ①20.0以下＝「Slow％D」が0～20％にある時は、売られすぎゾーンと見て「買いサイン」
      
      if(curr_st_vOrderIndexes.STOC_VAL > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.STOC_VAL < 20.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      // ②ゴールデンクロスがデッドクロスより近い

      if(curr_st_vOrderIndexes.STOC_GC > INT_VALUE_MIN 
          && curr_st_vOrderIndexes.STOC_DC > INT_VALUE_MIN ) {      
         if(curr_st_vOrderIndexes.STOC_GC < curr_st_vOrderIndexes.STOC_DC) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      
      // 4 RCI:RCI
      // ①-80.0以下。買いで利益が出るのは-80％付近。
      //  －80以下の水準から－80以上になったとき=https://www.jibunbank.co.jp/products/foreign_deposit/chart/help/rci/
      if(curr_st_vOrderIndexes.RCI_VAL > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.RCI_VAL < -80.0) {
            satisfyPoint++;
            satisfyPointALL++;   
         }
         else {
            satisfyPointALL++;
         }
      }

   }
      
   if(mBuySellProfitLoss == vBUY_LOSS
      || mBuySellProfitLoss == vSELL_PROFIT) {
      //
      // 買い＆損失、売り＆利益
      //
      // 1 移動平均:MA
      // ①ゴールデンクロスがデッドクロスより遠い
      if(curr_st_vOrderIndexes.MA_GC > INT_VALUE_MIN 
          && curr_st_vOrderIndexes.MA_DC > INT_VALUE_MIN ) {
         if(curr_st_vOrderIndexes.MA_GC > curr_st_vOrderIndexes.MA_DC) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      // ②傾きが負
      if(curr_st_vOrderIndexes.MA_Slope5 > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.MA_Slope5 < 0.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      if(curr_st_vOrderIndexes.MA_Slope25 > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.MA_Slope25 < 0.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      if(curr_st_vOrderIndexes.MA_Slope75 > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.MA_Slope75 < 0.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }      
      // 2 ボリンジャーバンドBB
      // ①nが-1以下
      if(curr_st_vOrderIndexes.BB_Width > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.BB_Width < -1.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }      
      // 3 一目均衡表:IK
      // ①IK_TENが負
      if(curr_st_vOrderIndexes.IK_TEN > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.IK_TEN < 0.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      // ②IK_CHIが負
      if(curr_st_vOrderIndexes.IK_CHI > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.IK_CHI < 0.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      // ③IK_LEGが負
      if(curr_st_vOrderIndexes.IK_LEG > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.IK_LEG < 0.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }   
      // 4 MACD:MACD
      // ①ゴールデンクロスがデッドクロスより遠い
      if(curr_st_vOrderIndexes.MACD_GC > INT_VALUE_MIN 
          && curr_st_vOrderIndexes.MACD_DC > INT_VALUE_MIN ) {
         if(curr_st_vOrderIndexes.MACD_GC > curr_st_vOrderIndexes.MACD_DC) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }      
      // 1 RSI:RSI
      // ①70.0以上。＝RSIが70％～80％を超えると買われ過ぎ、
      if(curr_st_vOrderIndexes.RSI_VAL > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.RSI_VAL > 70.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      // 2 ストキャスティクス:STOC
      // ①80.0以上。＝80～100％にある時は、買われすぎゾーンと見て「売りサイン」
      if(curr_st_vOrderIndexes.STOC_VAL > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.STOC_VAL > 80.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
      // ②ゴールデンクロスがデッドクロスより遠い
      if(curr_st_vOrderIndexes.STOC_GC > INT_VALUE_MIN 
          && curr_st_vOrderIndexes.STOC_DC > INT_VALUE_MIN ) {
         if(curr_st_vOrderIndexes.STOC_GC > curr_st_vOrderIndexes.STOC_DC) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }

      // 4 RCI:RCI
      // ①80.0以上。売りで利益が出るのは+80％付近。
      //  ＋80以上の水準から＋80以下になったとき=https://www.jibunbank.co.jp/products/foreign_deposit/chart/help/rci/
      if(curr_st_vOrderIndexes.RCI_VAL > DOUBLE_VALUE_MIN) {
         if(curr_st_vOrderIndexes.RCI_VAL > 80.0) {
            satisfyPoint++;
            satisfyPointALL++;
         }
         else {
            satisfyPointALL++;
         }
      }
   }


   if(satisfyPointALL == 0) {
      return false;
   } 

   double rate = (double)satisfyPoint / (double)satisfyPointALL * 100.0;

   if( rate >= GENERALRULE_PER) {

      return true;
   }
   else {

      return false;
   }
}

// st_vOrders[i]に登録されている仮想取引（意味のあるものに限る）の個数を返す
int get_vOrdersNum(){
   int count = 0;
   int i;
   for(i = 0; i < VTRADENUM_MAX; i++)  {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }
      if(StringLen(st_vOrders[i].strategyID) > 0  // 戦略名（マジックナンバー相当）が空欄ではないこと
         && st_vOrders[i].ticket > 0              // チケット番号が0より大きいこと
         && StringLen(st_vOrders[i].symbol) > 0   // 通貨ペアが空欄ではないこと
         && st_vOrders[i].openTime > 0            // 約定日が0ではないこと
         ) {
         count++;
      }
   }
   return count;
}         

int get_vOrdersNum(string mStrategy){
   int count = 0;
   int i;
   for(i = 0; i < VTRADENUM_MAX; i++)  {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }
      if(StringFind(mStrategy, st_vOrders[i].strategyID, 0) >= 0  // 戦略名がmStrategy(=08WPR)を含むこと
         && st_vOrders[i].ticket > 0              // チケット番号が0より大きいこと
         && StringLen(st_vOrders[i].symbol) > 0   // 通貨ペアが空欄ではないこと
         && st_vOrders[i].openTime > 0            // 約定日が0ではないこと
         ) {
         count++;
      }
   }
   return count;
}  

// 途中で空欄があっても最後まで登録済み取引を検索する
int get_vOrdersNum_SeekALL(){
   int count = 0;
   int i;
   for(i = 0; i < VTRADENUM_MAX; i++)  {
      if(StringLen(st_vOrders[i].strategyID) > 0  // 戦略名（マジックナンバー相当）が空欄ではないこと
         && st_vOrders[i].ticket > 0              // チケット番号が0より大きいこと
         && StringLen(st_vOrders[i].symbol) > 0   // 通貨ペアが空欄ではないこと
         && st_vOrders[i].openTime > 0            // 約定日が0ではないこと
         ) {
         count++;
      }
   }
   return count;
}         


// 引数mStrategyの戦略名を持つ仮想取引に対してflooring関数は実行しない時、trueを返す。
bool avoid_v_flooringSL(string mStrategy) {
   bool ret = true;

   if(StringCompare(mStrategy, g_StratName01) == 0) { // g_StratName01=Frac
      ret = false;
   }
   if(StringCompare(mStrategy, g_StratName24) == 0) { // g_StratName24=Zigzag
      ret = false;
   }

   return true;
}

// 引数mStrategyの戦略名を持つ仮想取引に対してTPとSLを使った強制決済は実行しない時、trueを返す。
bool avoid_v_do_ForcedSettlement(string mStrategy) {
   bool ret = false;

   if(StringLen(mStrategy) > 0 && StringCompare(mStrategy, g_StratName01) == 0) { // g_StratName01=Frac
      ret = true;
   }
   if(StringLen(mStrategy) > 0 && StringCompare(mStrategy, g_StratName24) == 0) { // g_StratName24=Zigzag
      ret = true;
   }

   return ret;
}

// 引数mStrategyにキーワードが入っていれば、v_update_AllOrdersTPSLを避けるためtrueを返す
bool avoid_v_update_AllOrdersTPSL(string mStrategy) {
   bool ret = false;

   if(StringLen(mStrategy) > 0 && StringCompare(mStrategy, g_StratName01) == 0) { // g_StratName01=Frac
      ret = true;
   }
   else if(StringLen(mStrategy) > 0 && StringCompare(mStrategy, g_StratName24) == 0) { // g_StratName24=Zigzag
      ret = true;
   }

   return ret;
}




//--------------------------------------------------------------------------+
//| 仮想取引において、Zigzagを使った損切値更新ロジックの方が、取引が持つ損切値より有利であれば更新する。 |
//| 実取引の損切値更新をする関数の仮想取引向け。                                        |
//|・2つ前の谷より直前の谷が高ければ、ロングのストップを直前の谷に更新する。                         |
//|・2つ前の山より直前の山が低ければ、ショートのストップを直前の山に更新する。                        |
//| ただし、以下を前提とする                                                        |
//| ロングエントリー                                                               |
//|・エントリー直後(損切値が0.0)に、直前の谷をストップとする。                                  |
//| ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、直近の値とする。 |
//| ショートエントリー                                                              |
//| ・エントリー直後(損切値が0.0)に、直前の山をストップとする。                                |
//|  ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、直近の値とする。|
//|                                                                         |
//|入力：マジックナンバーと通貨ペア。                                                    | 
//|出力：1件でも失敗すれば、falseを返す。                                              |
//--------------------------------------------------------------------------+
bool update_v_AllOrdersSLZigzag(string mStrategy, // 戦略名。
                                string mSymbol,    // 通貨ペア
                                int    mLastMountORBottom,
                                double &mZigTop[],
                                double &mZigBottom[]
                              ) {
   int i = 0;
   bool ret = true;
   double long_SL_Cand  = 0.0; // ロングの損切値候補
   double short_SL_Cand = 0.0; // ショートの損切値候補
   int mFlag = -1;             // OederModifyの返り値
   // 直近がZigzagの谷であれば、ロングの損切値候補を計算する。
   // ただし、2つ前の谷より直前の谷が高い場合とし、直前の谷の値を候補とする。 
   if( (mLastMountORBottom == ZIGZAG_MOUNT) 
       && (NormalizeDouble(mZigBottom[0], global_Digits) > NormalizeDouble(mZigBottom[1], global_Digits) && mZigBottom[1] > 0.0)) {
         long_SL_Cand = mZigBottom[0];
   }
   // 直近がZigzagの山であれば、ショートの損切値候補を計算する。
   // ただし、2つ前の山より直前の山が低い場合とし、直前の山の値を候補とする。 
   else if( (mLastMountORBottom == ZIGZAG_BOTTOM)
            && (NormalizeDouble(mZigTop[0], global_Digits) < NormalizeDouble(mZigTop[1], global_Digits) && mZigTop[0] > 0.0)) {
         short_SL_Cand = mZigTop[0];
   }
   else {
      ret = false;
   }

   if(long_SL_Cand <= 0.0 && short_SL_Cand <= 0.0) {
      ret = false;   
   }
   // この手前までに問題が発生していたら、以降の処理は行わない。
   if(ret == false) {
      return ret;
   }

   // 口座情報を取得する。
   double mMarketinfoMODE_ASK = MarketInfo(mSymbol,MODE_ASK);
   double mMarketinfoMODE_BID = MarketInfo(mSymbol,MODE_BID);
   double mMarketinfoMODE_POINT = global_Points;
   double mMarketinfoMODE_STOPLEVEL = global_StopLevel;
 
   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0) {
         break;
      }
      if(st_vOrders[i].openTime > 0 && st_vOrders[i].closeTime <= 0)  {
         if( StringLen(st_vOrders[i].strategyID) > 0 && StringLen(mStrategy) > 0 && StringCompare(st_vOrders[i].strategyID, mStrategy) == 0) {
            if(StringLen(st_vOrders[i].symbol) > 0 && StringLen(mSymbol) > 0 && StringCompare(st_vOrders[i].symbol, mSymbol) == 0) {
               int    mTicket          = st_vOrders[i].ticket;
               double mOpen            = st_vOrders[i].openPrice;
               double mOrderStopLoss   = st_vOrders[i].orderStopLoss;
               double mOrderTakeProfit = st_vOrders[i].orderTakeProfit;
               int    mBuySell         = st_vOrders[i].orderType;
    
              // ロングの場合の損切更新
               if(mBuySell == OP_BUY) {
                  // 注目しているOrderが、エントリー直後(損切値が0.0)の時は、
                  // ・エントリー直後(損切値が0.0)に、直前の谷をストップとする。 
                  // ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、直近の値とする。 
                  if(mOrderStopLoss <= 0.0) {
                     long_SL_Cand = mZigBottom[0];
                     if(long_SL_Cand < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // 損切値の更新は、より有利になる場合限定する。
                        if(NormalizeDouble(mOrderStopLoss, global_Digits) < NormalizeDouble(long_SL_Cand, global_Digits)) {
                           st_vOrders[i].orderStopLoss = long_SL_Cand;
                        }

                     }
                     else {
                        // 設定可能な最小値を損切値に設定していたが、性能が悪すぎた。
                        // ZZから計算される損切値以外は設定しない。
                        // st_vOrders[i].orderStopLoss = NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble((1+mMarketinfoMODE_STOPLEVEL) * mMarketinfoMODE_POINT, global_Digits) ;
                        // 
                        // long_SL_Cand と 設定可能最小値との関係によらず、long_SL_Cand を設定する。
                        // ただし、損切値の更新は、より有利になる場合限定する。
                        if(NormalizeDouble(mOrderStopLoss, global_Digits) < NormalizeDouble(long_SL_Cand, global_Digits)) {
                           st_vOrders[i].orderStopLoss = long_SL_Cand;
                        }

                     }
                  }
                  // ①mOrderStopLoss<=0.0　
                  //   または　②mOrderStopLoss > 0.0 かつ long_SL_Cand > mOrderStopLoss 
                  //             かつ long_SL_Cand < mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT
                  if( (mOrderStopLoss <= 0.0 && long_SL_Cand  > 0.0)   // 損切値が設定されていなければ、候補値直前の谷をそのまま使う。
                      || (mOrderStopLoss > 0.0 && long_SL_Cand  > 0.0  // 損切値が設定されていれば、候補値の方が損失が少なくなる時に設定する。
                            && NormalizeDouble(long_SL_Cand, global_Digits) > NormalizeDouble(mOrderStopLoss, global_Digits) 
                         ) 
                    ) {
                     if(NormalizeDouble(long_SL_Cand, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID, global_Digits) - NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // 損切値の更新は、より有利になる場合限定する。
                        if(NormalizeDouble(mOrderStopLoss, global_Digits) < NormalizeDouble(long_SL_Cand, global_Digits)) {
                           st_vOrders[i].orderStopLoss = long_SL_Cand;
                        }

                     }
                  }
               }
               // ショートの場合の損切更新
               else if(mBuySell == OP_SELL) {
                  // 注目しているOrderが、エントリー直後(損切値が0.0)の時は、               
                  //| ・エントリー直後(損切値が0.0)に、直前の山をストップとする。 
                  //|  ただし、mMarketinfoMODE_STOPLEVELを使った制約により直前の谷を使えない場合は、直近の値とする。
                  if(mOrderStopLoss <= 0.0) {
                     short_SL_Cand = mZigTop[0];
                     if(NormalizeDouble(short_SL_Cand, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // 損切値の更新は、より有利になる場合限定する。
                        if(NormalizeDouble(mOrderStopLoss, global_Digits) > NormalizeDouble(short_SL_Cand, global_Digits)) {
                           st_vOrders[i].orderStopLoss = short_SL_Cand;
                        }
                        else if(NormalizeDouble(mOrderStopLoss, global_Digits) <= 0.0) {
                           st_vOrders[i].orderStopLoss = short_SL_Cand;                        
                        }                        

                     }
                     else {
                        // 設定可能な最小値を損切値に設定していたが、性能が悪すぎた。
                        // ZZから計算される損切値以外は設定しない。
                        // st_vOrders[i].orderStopLoss = NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble((1+mMarketinfoMODE_STOPLEVEL) * mMarketinfoMODE_POINT, global_Digits);
                        // 
                        // short_SL_Cand と 設定可能最大値との関係によらず、long_SL_Cand を設定する。
                        // ただし、損切値の更新は、より有利になる場合限定する。
                        if(NormalizeDouble(mOrderStopLoss, global_Digits) > NormalizeDouble(short_SL_Cand, global_Digits)) {
                           st_vOrders[i].orderStopLoss = long_SL_Cand;
                        }
                        else if(NormalizeDouble(mOrderStopLoss, global_Digits) <= 0.0) {
                           st_vOrders[i].orderStopLoss = short_SL_Cand;                        
                        }                        

                     }
                  }
                  // ①mOrderStopLoss<=0.0　
                  //   または　②mOrderStopLoss > 0.0 かつ short_SL_Cand < mOrderStopLoss 
                  //             かつ short_SL_Cand > mMarketinfoMODE_BID + mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT
                  //             かつ　mOpen　<= short_SL_Cand 損切設定を更新するのは、利益が見込める時のみ
                  
                  if( (mOrderStopLoss <= 0.0 && short_SL_Cand > 0.0)    // 損切値が設定されていなければ、候補値直前の山をそのまま使う。
                      || (mOrderStopLoss > 0.0 && short_SL_Cand > 0.0   // 損切値が設定されていれば、候補値の方が損失が少なくなる時に設定する。
                          && NormalizeDouble(short_SL_Cand, global_Digits) < NormalizeDouble(mOrderStopLoss, global_Digits) 
                          )
                    ){
                     if(short_SL_Cand > NormalizeDouble(mMarketinfoMODE_ASK, global_Digits) + NormalizeDouble(mMarketinfoMODE_STOPLEVEL * mMarketinfoMODE_POINT, global_Digits)) {
                        // 損切値の更新は、より有利になる場合限定する。
                        if(NormalizeDouble(mOrderStopLoss, global_Digits) > NormalizeDouble(short_SL_Cand, global_Digits)) {
                           st_vOrders[i].orderStopLoss = short_SL_Cand;
                        }
                        else if(NormalizeDouble(mOrderStopLoss, global_Digits) <= 0.0) {
                           st_vOrders[i].orderStopLoss = short_SL_Cand;                        
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


// 指定した戦略の仮想取引用パラメータを作成する。g_StratName25 = "25PIN"
bool create_vOptParams(string mStrategy   // 指定した戦略の仮想取引用パラメータを作成する。g_StratName25 = "25PIN"
                       ) {
   int count = 0;
//   int TP_PIPS_count;
 //  int SL_PIPS_PER_count;

   return true;
}



//
// 構造体配列st_vOrderPLs[i]をst_vOrderPLs[i].ProfitFactorの大きい順に並べ替える。
//
bool sort_st_vOrderPLs_PF(st_vOrderPL &m_st_vOrderPLs[], // 出力：ソート結果
                          int          m_SortDESCASC     // DESC（降順）なら+1、ASC(昇順）なら-1
                              ) {
   int i;
   int j;
   int n;
   
   if(m_SortDESCASC != g_vSortDESC && m_SortDESCASC != g_vSortASK) {
      return false;
   }
   
   n = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(StringLen(m_st_vOrderPLs[i].strategyID) == 0) {
         break;
      }
      else {
         n++;
      }
   }

   if(n <= 0) {
      return true;
   }

   for ( j = 0; j < n-1; j++ ) {
      for ( i = j+1; i < n; i++ ) {
         if (m_SortDESCASC == 1 && m_st_vOrderPLs[j].ProfitFactor < m_st_vOrderPLs[i].ProfitFactor) {

            swap(m_st_vOrderPLs[i], m_st_vOrderPLs[j]);

         }
         if (m_SortDESCASC == -1 && m_st_vOrderPLs[j].ProfitFactor >= m_st_vOrderPLs[i].ProfitFactor) {
            swap(m_st_vOrderPLs[i], m_st_vOrderPLs[j]);
         }
      }
   }

   return true;
}

//
// 構造体配列st_vOrderPLs[i]をst_vOrderPLs[i].Profit（＝実現益＋評価益）＋st_vOrderPLs[i].Loss（＝実現損＋評価損）の大きい順に並べ替える。
//
bool sort_st_vOrderPLs_PL(st_vOrderPL &m_st_vOrderPLs[], // 出力：ソート結果
                          int          m_SortDESCASC     // DESC（降順）なら+1、ASC(昇順）なら-1
) {
   int i;
   int j;
   int n;

   if(m_SortDESCASC != g_vSortDESC && m_SortDESCASC != g_vSortASK) {
      return false;
   }

   n = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(StringLen(m_st_vOrderPLs[i].strategyID) == 0) {
         break;
      }
      else {
         n++;
      }
   }

   if(n <= 0) {
      return true;
   }

   for ( j = 0; j < n-1; j++ ) {
      for ( i = j+1; i < n; i++ ) {
         if (m_SortDESCASC == 1 && m_st_vOrderPLs[j].Profit + m_st_vOrderPLs[j].Loss < m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss) {
            swap(m_st_vOrderPLs[i], m_st_vOrderPLs[j]);
         }
         else if(m_SortDESCASC == -1 && m_st_vOrderPLs[j].Profit + m_st_vOrderPLs[j].Loss >= m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss) {
            swap(m_st_vOrderPLs[i], m_st_vOrderPLs[j]);
         }
         
      }
   }

   return true;
}



//
// 構造体配列st_vOrderPLs[i]をst_vOrderPLs[i].Profit（＝実現益＋評価益）＋st_vOrderPLs[i].Loss（＝実現損＋評価損）の大きい順に並べ替える。
//
bool sort_st_vOrderPLs_TradeNUM(st_vOrderPL &m_st_vOrderPLs[], // 出力：ソート結果
                                int          m_SortDESCASC     // DESC（降順）なら+1、ASC(昇順）なら-1
) {
   int i;
   int j;
   int n;

   if(m_SortDESCASC != g_vSortDESC && m_SortDESCASC != g_vSortASK) {
      return false;
   }
   n = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(StringLen(m_st_vOrderPLs[i].strategyID) == 0) {
         break;
      }
      else {
         n++;
      }
   }

   if(n <= 0) {
      return true;
   }

   for ( j = 0; j < n-1; j++ ) {
      for ( i = j+1; i < n; i++ ) {
         if (m_SortDESCASC == 1 
             && m_st_vOrderPLs[j].win + m_st_vOrderPLs[j].lose + m_st_vOrderPLs[j].even < m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even) {
            swap(m_st_vOrderPLs[i], m_st_vOrderPLs[j]);
         }
         else if(m_SortDESCASC == -1 
                 && m_st_vOrderPLs[j].win + m_st_vOrderPLs[j].lose + m_st_vOrderPLs[j].even >= m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even) {
            swap(m_st_vOrderPLs[i], m_st_vOrderPLs[j]);
         }
         
      }
   }

   return true;
}

// 抽出元m_st_vOrderPLs[]の中から、引数mPF以上のプロフィットファクターを持つ要素を選択し、
// 抽出結果m_result_st_vOrderPLs[]に入れる
// 返り値は、抽出した件数。
int select_st_vOrderPLs_byPF(st_vOrderPL &m_st_vOrderPLs[],       // 抽出元
                             double mPF,                          // 抽出条件に使うプロフィットファクタ 
                             int    mGreaterLower,                // mPF以上を選ぶなら1、mPFと一致なら0、mPF以下なら-1
                             st_vOrderPL &m_result_st_vOrderPLs[] // 出力：抽出結果
                              ) {  
   if(mGreaterLower != 1 && mGreaterLower != 0 && mGreaterLower != -1) {
      printf( "[%d]VT select_st_vOrderPLs_byPFの引数エラー。mGreaterLower=%d" , __LINE__, mGreaterLower);
      return -1;
   }
printf( "[%d]VT 確認　PF=%s以上か？" , __LINE__, DoubleToStr(mPF, global_Digits));

 
   // 抽出結果の初期化
   init_st_vOrderPLs(m_result_st_vOrderPLs);

   int i; 
   int count = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(m_st_vOrderPLs[i].analyzeTime <= 0
         || StringLen(m_st_vOrderPLs[i].strategyID) == 0) {
         break;
      }
      else {
printf( "[%d]VT 確認　%s の　PF=%s が引数のPF=%s以上か？" , __LINE__, m_st_vOrderPLs[i].strategyID, DoubleToStr(m_st_vOrderPLs[i].ProfitFactor, global_Digits) , DoubleToStr(mPF, global_Digits));

         if(mGreaterLower == g_Greater_Eq && NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits) >= NormalizeDouble(mPF, global_Digits)) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
         else if(mGreaterLower == g_Lower_Eq && NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits) <= NormalizeDouble(mPF, global_Digits)) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
         else if(NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits) == NormalizeDouble(mPF, global_Digits)) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
      }
   }

   return count;
}


int select_st_vOrderPLs_byPF(st_vOrderPL &m_st_vOrderPLs[],       // 抽出元
                             double       mPF,                    // 抽出条件に使うプロフィットファクタ 
                             int          mGreaterLower,          // mPF以上を選ぶなら1、mPFと一致なら0、mPF以下なら-1
                             st_vOrderPL &m_result_st_vOrderPLs[],// 出力：抽出結果
                             double      &m_maxPF,                // 出力：最大PF値
                             double      &m_maxPL,                // 出力：最大損益
                             int         &m_maxTradeNum           // 出力：最大取引数
                            ) {  
   if(mGreaterLower != 1 && mGreaterLower != 0 && mGreaterLower != -1) {
      printf( "[%d]VT select_st_vOrderPLs_byPFの引数エラー。mGreaterLower=%d" , __LINE__, mGreaterLower);
      return -1;
   }
printf( "[%d]VT 確認　PF=%s以上か？" , __LINE__, DoubleToStr(mPF, global_Digits));
 
   // 抽出結果の初期化
   init_st_vOrderPLs(m_result_st_vOrderPLs);

   m_maxPF       = DOUBLE_VALUE_MIN;
   m_maxPL       = DOUBLE_VALUE_MIN;
   m_maxTradeNum = INT_VALUE_MIN;


   int i; 
   int count = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(m_st_vOrderPLs[i].analyzeTime <= 0
         || StringLen(m_st_vOrderPLs[i].strategyID) == 0) {
         break;
      }
      else {
      
         if(mGreaterLower == g_Greater_Eq && NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits) >= NormalizeDouble(mPF, global_Digits)) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );

               // PFと損益、取引数の最大値を更新する。
               if(m_maxPF <= m_st_vOrderPLs[i].ProfitFactor) {
                  m_maxPF = NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits);
               }
               if(m_maxPL <= NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) ) {
                  m_maxPL = NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits);
               }               
               if(m_maxTradeNum <= m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even) {
                  m_maxTradeNum = m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even;
               }
                             
            count++;
         }
         else if(mGreaterLower == g_Lower_Eq && NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits) <= NormalizeDouble(mPF, global_Digits)) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );

               // PFと損益、取引数の最大値を更新する。
               if(m_maxPF <= m_st_vOrderPLs[i].ProfitFactor) {
                  m_maxPF = NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits);
               }
               if(m_maxPL <= NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) ) {
                  m_maxPL = NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits);
               }               
               if(m_maxTradeNum <= m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even) {
                  m_maxTradeNum = m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even;
               }

            count++;
         }
         else if(NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits) == NormalizeDouble(mPF, global_Digits)) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );

               // PFと損益、取引数の最大値を更新する。
               if(m_maxPF <= m_st_vOrderPLs[i].ProfitFactor) {
                  m_maxPF = NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits);
               }
               if(m_maxPL <= NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) ) {
                  m_maxPL = NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits);
               }               
               if(m_maxTradeNum <= m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even) {
                  m_maxTradeNum = m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even;
               }

            count++;
         }
      }
   }
printf( "[%d]VT PFが引数のPF=%s以上か？" , __LINE__, DoubleToStr(mPF, global_Digits));
output_vOrderPLs(m_result_st_vOrderPLs);
   return count;
}



// 抽出元m_st_vOrderPLs[]の中から、引数mPL以上の損益(m_st_vOrderPLs[].Profit + m_st_vOrderPLs[].Loss)を持つ要素を選択し、
// 抽出結果m_result_st_vOrderPLs[]に入れる
// 返り値は、抽出した件数。
int select_st_vOrderPLs_byPL(st_vOrderPL &m_st_vOrderPLs[],       // 抽出元
                             double mPL,                          // 抽出条件に使う損益 
                             int    mGreaterLower,                // mPL以上を選ぶなら1、mPLと一致なら0、mPL以下なら-1
                             st_vOrderPL &m_result_st_vOrderPLs[] // 出力：抽出結果
                              ) {  
   // 抽出結果の初期化
   init_st_vOrderPLs(m_result_st_vOrderPLs);

   int i; 
   int count = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(m_st_vOrderPLs[i].analyzeTime <= 0
         || StringLen(m_st_vOrderPLs[i].strategyID) == 0) {
         break;
      }
      else {
         if(mGreaterLower == g_Greater_Eq && DoubleToStr(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) >= mPL) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
         else if(mGreaterLower == g_Lower_Eq && DoubleToStr(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) <= mPL) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
         else if(mGreaterLower == g_Equal && DoubleToStr(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) == mPL) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
      }
   }
   return count;
}

int select_st_vOrderPLs_byPL(st_vOrderPL &m_st_vOrderPLs[],       // 抽出元
                             double mPL,                          // 抽出条件に使う損益 
                             int    mGreaterLower,                // mPL以上を選ぶなら1、mPLと一致なら0、mPL以下なら-1
                             st_vOrderPL &m_result_st_vOrderPLs[],// 出力：抽出結果
                             double      &m_maxPF,                // 出力：最大PF値
                             double      &m_maxPL,                // 出力：最大損益
                             int         &m_maxTradeNum           // 出力：最大取引数
                             
                              ) {  
   // 抽出結果の初期化
   init_st_vOrderPLs(m_result_st_vOrderPLs);

   int i; 
   int count = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(m_st_vOrderPLs[i].analyzeTime <= 0
         || StringLen(m_st_vOrderPLs[i].strategyID) == 0) {
         break;
      }
      else {
         if(mGreaterLower == g_Greater_Eq && DoubleToStr(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) >= mPL) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );

            // PFと損益、取引数の最大値を更新する。
            if(m_maxPF <= m_st_vOrderPLs[i].ProfitFactor) {
               m_maxPF = NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits);
            }
            if(m_maxPL <= NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) ) {
               m_maxPL = NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits);
            }               
            if(m_maxTradeNum <= m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even) {
               m_maxTradeNum = m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even;
            }
                             
            count++;
         }
         else if(mGreaterLower == g_Lower_Eq && DoubleToStr(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) <= mPL) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );

            // PFと損益、取引数の最大値を更新する。
            if(m_maxPF <= m_st_vOrderPLs[i].ProfitFactor) {
               m_maxPF = NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits);
            }
            if(m_maxPL <= NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) ) {
               m_maxPL = NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits);
            }               
            if(m_maxTradeNum <= m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even) {
               m_maxTradeNum = m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even;
            }

            count++;
         }
         else if(mGreaterLower == g_Equal && DoubleToStr(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) == mPL) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );

            // PFと損益、取引数の最大値を更新する。
            if(m_maxPF <= m_st_vOrderPLs[i].ProfitFactor) {
               m_maxPF = NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits);
            }
            if(m_maxPL <= NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) ) {
               m_maxPL = NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits);
            }               
            if(m_maxTradeNum <= m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even) {
               m_maxTradeNum = m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even;
            }

            count++;
         }
      }
   }
printf( "[%d]VT 損益が引数のmPL=%s以上か？" , __LINE__, DoubleToStr(mPL, global_Digits));
output_vOrderPLs(m_result_st_vOrderPLs);
   
   return count;
}
// 抽出元m_st_vOrderPLs[]の中から、引数mWinPERLoseRate以上の勝利率(＝勝ち数÷負け数)を持つ要素を選択し、
// 抽出結果m_result_st_vOrderPLs[]に入れる
// 返り値は、抽出した件数。
int select_st_vOrderPLs_byWinningPERLoseRate(st_vOrderPL &m_st_vOrderPLs[],       // 抽出元
                                             double      mWinPERLoseRate,         // 抽出条件に使う勝率
                                             int         mGreaterLower,           // mTradeNum以上を選ぶなら1、mTradeNumと一致なら0、mTradeNum以下なら-1
                                             st_vOrderPL &m_result_st_vOrderPLs[] // 出力：抽出結果
                                           ) {  
   // 抽出結果の初期化
   init_st_vOrderPLs(m_result_st_vOrderPLs);
   int i; 
   int count = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(m_st_vOrderPLs[i].analyzeTime <= 0
         || StringLen(m_st_vOrderPLs[i].strategyID) == 0) {
         break;
      }
      else {
         double tmpWinLose; // 注目している要素の勝利率
         tmpWinLose = calc_WinningPERLoseRate(m_st_vOrderPLs[i].win, m_st_vOrderPLs[i].lose);
        
         if(mGreaterLower == g_Greater_Eq && tmpWinLose >= mWinPERLoseRate) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
         else if(mGreaterLower == g_Lower_Eq && tmpWinLose <= mWinPERLoseRate) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
         else if(mGreaterLower == g_Equal && tmpWinLose == mWinPERLoseRate) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
      }
   }
   
   return count;
}

// 抽出元m_st_vOrderPLs[]の中から、引数mStrategyIDを持つ要素を選択し、
// 抽出結果m_result_st_vOrderPLs[]に入れる
// 引数mStrategyIDを使って、戦略名"25PIN"などで絞り込みをするが、引数mStrategyIDが""（＝長さ0)の場合は、全件を処理対象とする。
// 返り値は、抽出した件数。
int select_st_vOrderPLs_byStrategyID(st_vOrderPL &m_st_vOrderPLs[],       // 抽出元
                             string mStrategyID,                          // 抽出条件に使う損益 
                             st_vOrderPL &m_result_st_vOrderPLs[] // 出力：抽出結果
                              ) {  
   // 抽出結果の初期化
   init_st_vOrderPLs(m_result_st_vOrderPLs);

   int i; 
   int count = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(m_st_vOrderPLs[i].analyzeTime <= 0
         || StringLen(m_st_vOrderPLs[i].strategyID) == 0) {
         break;
      }
      else {
         if(StringLen(mStrategyID) > 0 || StringFind(m_st_vOrderPLs[i].strategyID, mStrategyID) >= 0) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
         else if(StringLen(mStrategyID)  == 0) {
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;         }
      }
   }
   return count;
}

// 抽出元m_st_vOrderPLs[]の中から、
// ①引数mWinPERLoseRate以上の勝利率(＝勝ち数÷負け数)。
// ②引数mTradeNum以上の取引数
// ③引数にはないが、損益の加重平均が０以上。
// を持つ要素を選択し、抽出結果m_result_st_vOrderPLs[]に入れる
// 返り値は、抽出した件数。
st_vOrderPL tmp_sv_vOrderPLs[VOPTPARAMSNUM_MAX];  // メモリサイズエラーを回避するため、グローバル変数とした。
int select_st_vOrderPLs_byOriginalRules(st_vOrderPL &m_st_vOrderPLs[],        // 抽出元
                                        int          mTradeNum_MIN,           // 取引数がこの値以上のパラメータセットを抽出する。
                                        double       mWinPERLoseRate_MIN,     // 勝率がこの値以上のパラメータセットを抽出する。
                                        double       m_PF_MIN,                // プロフィットファクターがこの値以上のパラメータセットを抽出する。
                                        st_vOrderPL &m_result_st_vOrderPLs[], // 出力：抽出結果
                                        double      &m_maxPF,                 // 出力：最大PF値。ただし、DOUBLE_VALUE_MAXは除く
                                        double      &m_maxPL,                 // 出力：最大損益
                                        int         &m_maxTradeNum            // 出力：最大取引数
                                           ) {  

                                           
   // 抽出結果の初期化
   init_st_vOrderPLs(m_result_st_vOrderPLs);
   init_st_vOrderPLs(tmp_sv_vOrderPLs);
   int i; 
   int count = 0;
   double maxWeightedAVG = DOUBLE_VALUE_MIN;
   m_maxPF       = DOUBLE_VALUE_MIN;
   m_maxPL       = DOUBLE_VALUE_MIN;
   m_maxTradeNum = INT_VALUE_MIN;

   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
  
      if(m_st_vOrderPLs[i].analyzeTime <= 0
         || StringLen(m_st_vOrderPLs[i].strategyID) == 0) {
         break;
      }
      else {
         double tmpWinLoseRate;    // 注目している要素の勝利率
         int    tmpWinLoseNum; // 注目している要素の取引総数
         double tmpWeightedAVG;// 注目している要素の損益の加重平均。加重平均は、最大５つある直近取引を(5 * 直近の損益 + 4*1つ前の損益 + 3*2つ前の損益・・・+1 *4つ前の損益) ÷　4とする。
         double tmpPF;
         
         // 注目している要素の勝率
         tmpWinLoseRate = NormalizeDouble(calc_WinningPERLoseRate(m_st_vOrderPLs[i].win, m_st_vOrderPLs[i].lose), global_Digits);

         // 注目している要素の取引数
         tmpWinLoseNum  = m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even;

         // 注目している要素の損益加重平均
         tmpWeightedAVG = NormalizeDouble(m_st_vOrderPLs[i].latestTrade_WeightedAVG, global_Digits);

         // 注目している要素のプロフィットファクタ
         tmpPF          = NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits);
printf( "[%d]PB 確認　オリジナルルールを満たすPLセット検索中　>%d< %s  分析時間=>%s< 勝率=%s  tmpWinLoseNum取引数=%s  tmpWeightedAVG=%s tmpPF=%s" , __LINE__ ,
i,
m_st_vOrderPLs[i].strategyID,
TimeToStr(m_st_vOrderPLs[i].analyzeTime),
DoubleToStr(tmpWinLoseRate, global_Digits),
DoubleToStr(tmpWinLoseNum, global_Digits),
DoubleToStr(tmpWeightedAVG, global_Digits),
DoubleToStr(tmpPF, global_Digits)
);      

         // 損益の加重平均が、正であること。            
         // 取引総数が、引数のmTradeNum_MIN以上であること
         // 勝利率が、引数のmWinPERLoseRate_MIN以上
         // プロフィットファクターが、引数のm_PF_MIN以上
         if(tmpWeightedAVG >= 0.0
            && tmpWinLoseNum  >= mTradeNum_MIN
            && tmpWinLoseRate >= mWinPERLoseRate_MIN
            && tmpPF          >= m_PF_MIN
            ) {
               // 条件を満たした要素を、出力用配列にコピーする
               copy_st_vOrderPL(m_st_vOrderPLs[i],      // コピー元
                                tmp_sv_vOrderPLs[count] // コピー先
                                );

               count++; // 条件を満たした要素数をカウントアップする
               // 抽出したパラメータセットのPFと損益、取引数の最大値を更新する。
               if(m_maxPF <= m_st_vOrderPLs[i].ProfitFactor && m_st_vOrderPLs[i].ProfitFactor < DOUBLE_VALUE_MAX) {
                  m_maxPF = NormalizeDouble(m_st_vOrderPLs[i].ProfitFactor, global_Digits);
               }
               if(m_maxPL <= NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits) ) {
                  m_maxPL = NormalizeDouble(m_st_vOrderPLs[i].Profit + m_st_vOrderPLs[i].Loss, global_Digits);
               }               
               if(m_maxTradeNum <= m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even) {
                  m_maxTradeNum = m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even;
               }
               // 加重平均の最大値を更新する。
               if(maxWeightedAVG <= tmpWeightedAVG) {
                  maxWeightedAVG = NormalizeDouble(tmpWeightedAVG, global_Digits);
               }

         }
      }
   }
   
   if(count <= 0) {
      return count;
   }
   
   // 抽出した結果を、出力用引数であるm_result_st_vOrderPLsにコピーする。
   int retCount = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(tmp_sv_vOrderPLs[i].analyzeTime <= 0
         || StringLen(tmp_sv_vOrderPLs[i].strategyID) == 0) {
         break;
      }
      else {
         tmpWeightedAVG = NormalizeDouble(tmp_sv_vOrderPLs[i].latestTrade_WeightedAVG, global_Digits);
         if(tmpWeightedAVG >= maxWeightedAVG) {
            copy_st_vOrderPL(tmp_sv_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[retCount] // コピー先
                            );
            retCount++;
         }
      }   
   }

printf( "[%d]PB 確認　オリジナルルールを満たすPLセット境界値 取引数=%d  勝率=%s  PF=%s" , __LINE__ ,
mTradeNum_MIN,
DoubleToStr(mWinPERLoseRate_MIN, global_Digits),
DoubleToStr(m_PF_MIN, global_Digits)
);  
output_vOrderPLs(m_result_st_vOrderPLs);
printf( "[%d]PB 確認ここまで" , __LINE__ );
   return retCount;
}

int select_st_vOrderPLs_byTradeNum(st_vOrderPL &m_st_vOrderPLs[],       // 抽出元
                                   int mTradeNum,                       // 抽出条件に使う取引数 
                                   int mGreaterLower,                // mTradeNum以上を選ぶなら1、mTradeNumと一致なら0、mTradeNum以下なら-1
                                   st_vOrderPL &m_result_st_vOrderPLs[] // 出力：抽出結果
                              ) {  
   // 抽出結果の初期化

   init_st_vOrderPLs(m_result_st_vOrderPLs);

   int i; 
   int count = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(m_st_vOrderPLs[i].analyzeTime <= 0
         || StringLen(m_st_vOrderPLs[i].strategyID) == 0) {
         break;
      }
      else {
      
         if(mGreaterLower == g_Greater_Eq && m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even >= mTradeNum) {         
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
         else if(mGreaterLower == g_Lower_Eq && m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even <= mTradeNum) {
         
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
         else if(mGreaterLower == g_Equal && m_st_vOrderPLs[i].win + m_st_vOrderPLs[i].lose + m_st_vOrderPLs[i].even == mTradeNum) {
         
            copy_st_vOrderPL(m_st_vOrderPLs[i],           // コピー元
                             m_result_st_vOrderPLs[count] // コピー先
                             );
            count++;
         }
         else {
         
         }
      }
   }
printf( "[%d]PB 確認　取引件数が、引数>%d<以上" , __LINE__, mTradeNum);
output_vOrderPLs(m_result_st_vOrderPLs);
   return count;
}



void swap(st_vOrderPL &y, st_vOrderPL &z ) {
   st_vOrderPL buf;
   copy_st_vOrderPL(y, buf);  // yをbufにコピー
   copy_st_vOrderPL(z, y);    // zをyにコピー   
   copy_st_vOrderPL(buf, z);  // bufをzにコピー
}


//
// 登録済みの仮想取引st_vOrders[]を出力する。
//
void output_st_vOrders() {
   int i;
   int buySell;

   for(i = 0; i < VTRADENUM_MAX; i++) {
      if(st_vOrders[i].openTime <= 0) {
         if(i <= 0) {
            printf("[%d]VT 登録中の仮想取引無し", __LINE__);
         }
         break;
      }
      buySell = st_vOrders[i].orderType;
      // 対象取引の属性値を取得する。
      string buf_vOrder = "";
         buf_vOrder = buf_vOrder + " No" + ZeroPadding(i, 5); //IntegerToString(i);
         buf_vOrder = buf_vOrder + " 戦略名：" + st_vOrders[i].strategyID;
         buf_vOrder = buf_vOrder + " 通貨ペア：" + st_vOrders[i].symbol;
         buf_vOrder = buf_vOrder + " チケット番号：" + IntegerToString(st_vOrders[i].ticket);
         buf_vOrder = buf_vOrder + " 時間軸：" + IntegerToString(st_vOrders[i].timeframe);
         if(buySell == OP_BUY) {
            buf_vOrder = buf_vOrder + " 売買=ロング" + IntegerToString(st_vOrders[i].ticket);
         }
         else {
            buf_vOrder = buf_vOrder + " 売買=ショート" + IntegerToString(st_vOrders[i].ticket);         
         }
         buf_vOrder = buf_vOrder + " 約定日：" + TimeToStr(st_vOrders[i].openTime);
         buf_vOrder = buf_vOrder + " 約定値：" + DoubleToStr(st_vOrders[i].openPrice);
         buf_vOrder = buf_vOrder + " 利確値：" + DoubleToStr(st_vOrders[i].orderTakeProfit);
         buf_vOrder = buf_vOrder + " 損切値：" + DoubleToStr(st_vOrders[i].orderStopLoss);
         buf_vOrder = buf_vOrder + " 決済日：" + TimeToStr(st_vOrders[i].closeTime);
         buf_vOrder = buf_vOrder + " 決済値：" + DoubleToStr(st_vOrders[i].closePrice);
         buf_vOrder = buf_vOrder + " 決済損益" + DoubleToStr(st_vOrders[i].closePL);
         buf_vOrder = buf_vOrder + " 評価日：" + TimeToStr(st_vOrders[i].estimateTime);
         buf_vOrder = buf_vOrder + " 評価値：" + DoubleToStr(st_vOrders[i].estimatePrice);
         buf_vOrder = buf_vOrder + " 評価損益" + DoubleToStr(st_vOrders[i].estimatePL);
         printf("[%d]VT 仮想取引全件出力 %s", __LINE__, buf_vOrder);
         
   }
}


// 仮想取引のうち、引数のtickNoと戦略名をキーとして、仮想取引の外部パラメータを格納するexternalParamを更新する。
void set_st_vOrder_ExternalParam(st_vOrder &m_st_vOrders[],
                                 int mtickNo,              // 仮想取引st_vOrderのticket 
                                 string mStrategyID,       // 仮想取引st_vOrderのstrategyID
                                 string mexternalParam     // 仮想取引st_vOrderのexternalParam
                                ) {
   int i;
   for(i = 0; i < VTRADENUM_MAX; i++) {  
      if(m_st_vOrders[i].openTime <= 0) {
         break;
      }
      if(m_st_vOrders[i].ticket == mtickNo
         && StringLen(m_st_vOrders[i].strategyID) > 0 && StringLen(mStrategyID) > 0 && StringCompare(m_st_vOrders[i].strategyID, mStrategyID) == 0
         ) {
         m_st_vOrders[i].externalParam = mexternalParam;
         break;
      }
   }                              
}


int get_st_vOrderPLsNum(st_vOrderPL &m_st_vOrderPLs[]) {
   int i;
   int count = 0;
   for(i = 0; i < VOPTPARAMSNUM_MAX; i++) {
      if(m_st_vOrderPLs[i].analyzeTime > 0) {
         count++;
      }
      else {
         return count;
      }
   }
   
   return INT_VALUE_MIN;
}




//
//
// 同じ内容の仮想取引注文を連続して発注する制御
// オープン中の仮想取引のうち、約定日が等しく、売買区分、戦略名が同じ仮想取引が存在すれば、
// trueを返す
// 
bool exist_same_vTrade_OpenTimeANDBuysellANDStrat(datetime m_TradeTime,    // 約定日
                                                              int      m_orderType,    // OPBUY, OP_SELL
                                                              string   m_Strategy    // 戦略名
                                                   ) {  
   int i;
   for(i = 0; i < VTRADENUM_MAX; i++) {  
      if(st_vOrders[i].openTime <= 0) {
         break;
      }      
      if(StringLen(st_vOrders[i].strategyID) > 0 && StringLen(m_Strategy) > 0 && StringCompare(st_vOrders[i].strategyID, m_Strategy) == 0
         && st_vOrders[i].openTime == m_TradeTime  // 約定日付が同じ
         && st_vOrders[i].orderType == m_orderType // 売買区分が同じ
         && (StringLen(st_vOrders[i].strategyID) > 0 && StringLen(m_Strategy) > 0 && StringCompare(st_vOrders[i].strategyID, m_Strategy) == 0 )// 戦略名が同じ
         && st_vOrders[i].closeTime <= 0           // オープンな取引
         ) {   
            return true;
      } 

   } 
         
   return false;
}

double calc_WinningPERLoseRate(int mWin,
                               int mLose) {
   double tmpWinLose = DOUBLE_VALUE_MIN; // 注目している要素の勝利率
   
   if(mLose == 0) {
      if(mWin > 0) {
         tmpWinLose = DOUBLE_VALUE_MAX;
      }
      else {
         tmpWinLose = 0.0;
      }
   }
   else {
      // 取引数は０より大で全勝の勝率は、DOUBLE_VALUE_MAX
      tmpWinLose = NormalizeDouble((double)mWin / (double)mLose, global_Digits);
   }


   return tmpWinLose;
}

bool add_latestTrade_st_vOrders(st_vOrderPL &m_st_vOrderPL,
                                datetime     m_openTime,     // 追加する取引の約定時刻
                                double       m_PL            // 追加する取引の損益
                                ) {
   datetime buf_latestTrade_time[];
   double   buf_latestTrade_PL[];
   ArrayResize(buf_latestTrade_time, HISTORICAL_NUM+1);
   ArrayResize(buf_latestTrade_PL, HISTORICAL_NUM+1);
   ArrayInitialize(buf_latestTrade_time, INT_VALUE_MIN);
   ArrayInitialize(buf_latestTrade_PL  , DOUBLE_VALUE_MIN);

   int i;

   // 一時ソート用配列にコピー
   for(i = 0; i < HISTORICAL_NUM; i++) {
      buf_latestTrade_time[i] = m_st_vOrderPL.latestTrade_time[i];
      buf_latestTrade_PL[i] = m_st_vOrderPL.latestTrade_PL[i];
   }
   // 一時ソート用配列に追加
   buf_latestTrade_time[HISTORICAL_NUM] = m_openTime;
   buf_latestTrade_PL[HISTORICAL_NUM]   = m_PL;
   
   // 一時ソート用配列を降順にソート
   int n = HISTORICAL_NUM + 1;
   int j;
   int k;
   for ( j = 0; j < n-1; j++ ) {
      for ( k = j + 1; k < n; k++ ) {
         if (buf_latestTrade_time[j] <= buf_latestTrade_time[k]) {
            datetime bufTime;
            double   bufPL;
            bufTime = buf_latestTrade_time[j];
            bufPL   = buf_latestTrade_PL[j];
            buf_latestTrade_time[j] = buf_latestTrade_time[k];
            buf_latestTrade_PL[j]   = buf_latestTrade_PL[k];
            buf_latestTrade_time[k] = bufTime;
            buf_latestTrade_PL[k]   = bufPL;
         }
      }
   }   

   // 一時ソート用配列の0-HISTORICAL_NUM-1までを配列にコピーする
   for(i = 0; i < HISTORICAL_NUM; i++) {
      m_st_vOrderPL.latestTrade_time[i] = buf_latestTrade_time[i];
      m_st_vOrderPL.latestTrade_PL[i]   = buf_latestTrade_PL[i];
   } 
/*
   // 損益の加重平均を計算する。
   double tmpWeightedAVG = 0.0;
   int countWeightedAVGNum = 0;
   int ii;
   for(ii = 0; ii < HISTORICAL_NUM; ii++) {
      if(m_st_vOrderPL.latestTrade_time[ii] <= 0) {
         break;
      }
      tmpWeightedAVG = tmpWeightedAVG + NormalizeDouble(m_st_vOrderPL.latestTrade_PL[ii] * (double)(HISTORICAL_NUM - ii), global_Digits);
      countWeightedAVGNum = countWeightedAVGNum + (HISTORICAL_NUM - ii);
   }
   if(countWeightedAVGNum > 0) {
      tmpWeightedAVG = NormalizeDouble(tmpWeightedAVG / countWeightedAVGNum, global_Digits);
   }
   else {
      tmpWeightedAVG = DOUBLE_VALUE_MIN;
   }
   m_st_vOrderPL.latestTrade_WeightedAVG = tmpWeightedAVG;
  */
   return false;                                
}                                


//
//
// 以下は参考情報
//
//
/*
【用いる指標】
指標の順位は、https://info.monex.co.jp/technical-analysis/column/005.htmlを参照
トレンド分析
1 移動平均:MA
　・ゴールデンクロス＝直近のクロスまでのシフト数:GC
　・デッドクロスの有無＝直近のクロスまでのシフト数:DC
　・傾き＝シフト5本、25本、75本の傾き:Slope

2 ボリンジャーバンドBB
  ・Close = 平均±n×σを満たすnの値。予想は、買いで利益が出るのはnが2以上。:Width

3 一目均衡表:IK
　・転換線 - 基準線のPIPS。転換線が基準線を上抜けたら買い/下抜けたら売り　→　予想は、買いで利益が出るのはPIPSが正の時。:TEN
 ・遅行線 - CloseのPIPS。遅行線がローソク足を上抜けたら買い/下抜けたら売り　→　予想は、買いで利益が出るのはPIPSが正の時。:CHI
　・（Close - 雲の近い方）のPIPS。ローソク足が雲を上抜けたら買い/下抜けたら売り　→　予想は、買いで利益が出るのはPIPSが正の時。:LEG


4 MACD:MACD
　・ゴールデンクロス＝直近のクロスまでのシフト数:GC
　・デッドクロスの有無＝直近のクロスまでのシフト数:DC

オシレーター分析
1 RSI:RSI
  ・0%～100%の間で推移する数値。RSIが70％～80％を超えると買われ過ぎ、反対に20％～30％を割り込むと売られ過ぎのため、予想は、買いで利益が出るのは20％～30％付近。:VAL

2 ストキャスティクス:STO
　・0%～100%の間で推移するスローストキャスティクスSlow％D。:SD
　　-「Slow％D」が0～20％にある時は、売られすぎゾーンと見て「買いサイン」。80～100％にある時は、買われすぎゾーンと見て「売りサイン」
　・「Slow％K」ラインが「Slow％D」を下から上に抜ける（ゴールデンクロス）＝直近のクロスまでのシフト数:SDGC
　・「Slow％K」ラインが「Slow％D」を上から下に抜ける（デッドクロス）＝直近のクロスまでのシフト数:SDDC
補足説明：
　ファーストストキャスティックスは、相場の動きに素早く反応するため、短期売買向きでダマシも多いのが欠点です。それを補う役割を果たすのがスローストキャスティクスで、一般的にはこちらを利用することが多い

3 酒田五法（ローソク足の組み合わせのため、除外）

4 RCI:RCI
  ・-100%～100%の間で推移する数値。予想は、買いで利益が出るのは-80％付近。売りで利益が出るのは+80％付近。:VAL
補足説明：
・計算期間をn日間としてRCIを算出する場合、n日間価格が上昇し続けると100%になり、逆に下落し続けると0%になります。
・n（パラメータ値）は“9”（日足）と設定する場合が多い。
・「買い」のシグナル
　売られ過ぎの－100％ラインに接近した後反転し、上昇し始めたタイミング
　底値圏から上昇後、-80％ラインを越えたタイミング
・「売り」のシグナル
　買われ過ぎの100％ラインに接近した後反落し、下落し始めたタイミング
　高値圏から下落後、80％ラインを下回ったタイミング
*/




//+------------------------------------------------------------------+












