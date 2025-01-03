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
      return ERROR;
   }

   // スプレッドが広がりすぎている時は、発注しない。
   if(MathAbs(mMarketinfoMODE_ASK - mMarketinfoMODE_BID) > get_Point(MAX_SPREAD_PIPS)) {
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


//|   ※ 引数で渡された利確値、損切値が、０より大きい場合に限り、OrderSendのコメント欄に、<TP>・・・</TP><SL>・・・</SL>を追加する。
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
                              mMarketinfoMODE_STOPLEVEL, // 14 MODE_STOPLEVEL  //point単位でストップレベルを取得 https://buco-bianco.com/mql4-marketinfo-function/
                              takeprofit, // 出力：利確値候補を渡す。売買区分とストップレベルを考慮して、設定可能であればそのままの値を返し、設定不可能であれば0を返す。
                              stoploss    // 出力：利確値候補を渡す。売買区分とストップレベルを考慮して、設定可能であればそのままの値を返し、設定不可能であれば0を返す。
                                );
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
}



// ストップレベルを使って、takeprofitとstoplossが設定できなければ、0にする
// ロングの利確takeprofitは、その時のASK＋ストップレベルより大きくなくてはならない。
// ロングの損切stoploss　は、その時のBID-ストップレベルより小さくなくてはならない。
// 参考資料：https://toushi-strategy.com/mt4/stoplevel/
// ショートの利確takeprofitは、その時のBID-ストップレベルより小さくなくてはならない。
// ショートの損切stoplossは、その時のASK+ストップレベルより大きくなくてはならない。
// 参考資料：https://toushi-strategy.com/mt4/stoplevel/　　から、推測。
void update_TPSL_with_StopLevel(int    mBuySell,     // 売買区分OP_SELL, OP_BUY
                                double mMarketinfoMODE_STOPLEVEL, // 14 MODE_STOPLEVEL  //point単位でストップレベルを取得 https://buco-bianco.com/mql4-marketinfo-function/
                                double &mTakeprofit, // 出力：利確値候補を渡す。売買区分とストップレベルを考慮して、設定可能であればそのままの値を返し、設定不可能であれば0を返す。
                                double &mStoploss    // 出力：利確値候補を渡す。売買区分とストップレベルを考慮して、設定可能であればそのままの値を返し、設定不可能であれば0を返す。
                                ) {
   // ロングの利確takeprofitは、その時のASK＋ストップレベルより大きくなくてはならない。
   // ロングの損切stoploss　は、その時のBID-ストップレベルより小さくなくてはならない。
   // 参考資料：https://toushi-strategy.com/mt4/stoplevel/
   //
   if(cmd == OP_BUY) {
      // takeprofitの判断。
      if(NormalizeDouble(mTakeprofit, global_Digits) > NormalizeDouble(mMarketinfoMODE_ASK + mMarketinfoMODE_STOPLEVEL, global_Digits)) {
         // mTakeprofitは更新しない。
      }
      else 
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
   if(cmd == OP_SELL) {
      // takeprofitの判断。
      if(mNormalizeDouble(Takeprofit, global_Digits) < NormalizeDouble(mMarketinfoMODE_BID - mMarketinfoMODE_STOPLEVEL, global_Digits)) {
         // mTakeprofitは更新しない。
      }
      else 
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