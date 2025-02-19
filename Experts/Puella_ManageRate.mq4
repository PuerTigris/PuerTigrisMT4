//+------------------------------------------------------------------+	
//| 　　                                         Puella_ManageRate.mq4 |	
//|       Copyright (c) 2019 トラの親(tora_no_oya) All rights reserved. |	
//|                                   http://nenshuuha.blog.fc2.com/ |
//+------------------------------------------------------------------+	
#property copyright "Copyright (c) 2019 トラの親(tora_no_oya) All rights reserved."				
#property link      "http://nenshuuha.blog.fc2.com/"						
//+------------------------------------------------------------------+	
//| ヘッダーファイル読込                                             |	
//+------------------------------------------------------------------+	
#include <stderror.mqh>	
#include <stdlib.mqh>	
#include <MQLMySQL.mqh>


//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	
extern int DROP_OLD_BEFORE = 100;  //ローカル時間TimeLocal()より、この値だけ以前のデータを削除する。負を設定すると100に変換。

//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	



//+------------------------------------------------------------------+	
//| 初期処理                                                         |	
//+------------------------------------------------------------------+	
int init()	
{	
   //外部パラメーターの整合性チェック
   if(DROP_OLD_BEFORE < 0) {
	DROP_OLD_BEFORE = 100;
   }
   return(0);	
}	
	
//+------------------------------------------------------------------+	
//| 終了処理                                                         |	
//+------------------------------------------------------------------+	
int deinit()	
{	

   //オブジェクトの削除	
   ObjectDelete("PGName");	
   return(0);	
}	
	
//+------------------------------------------------------------------+	
//| メイン処理                                                       |	
//+------------------------------------------------------------------+	
int start()	
{
   string currPair  = Symbol();
   datetime timeframe = Period();
   string company = AccountServer();
   updatePrice(company, currPair, timeframe);

}


//+------------------------------------------------------------------+
//| 自作関数                                                         |	
//+------------------------------------------------------------------+	
//pricetableに、ASK, BID, 書き込み時間等をを登録する。        
//テーブル定義は、次のとおり。
//Table名：pricetable
//company:String   FXTF-demoなど
//currPair:String   USDJPY-cdなど
//intTimeFrame: PERIOD_M1 = 1 = 1分、PERIOD_M5 = 5 = 5分等。
//Bid:double
//Ask:double
//updateTime:int = datetime   
//入力：company = サーバ名, currPair = 通貨ペア, timeframe = タイムフレーム
//返り値： 正常終了は、0。失敗は、-1。
int updatePrice(string company, string currPair, datetime timeframe)  {

   int rtnFlag = 0;  //正常終了時の返り値0を設定する。

   //入力値チェック
   //なし
   
   //
   //DBに接続する。
   //
   string Host;     //データベースサーバ。IPアドレス。
   string User;     //データベースへのログイン名
   string Password; //データベースへのログイン時パスワード
   string Database; //アクセス先データベースオブジェクト名
   string Socket;   //データベースへの接続先ソケット番号
   int Port;        //接続先ポート番号
   int ClientFlag;  //データベースに複数処理させるためのフラグ
   int DB;          // データベース接続時の識別子 
   string INI = TerminalInfoString(TERMINAL_PATH)+"\\MQL4\\Scripts\\MyConnection.ini";

   // INIファイルから、DB接続情報を取得する。
   Host = ReadIni(INI, "MYSQL", "Host");
   User = ReadIni(INI, "MYSQL", "User");
   Password = ReadIni(INI, "MYSQL", "Password");
   Database = ReadIni(INI, "MYSQL", "Database");
   Port     = (int)StringToInteger(ReadIni(INI, "MYSQL", "Port"));
   Socket   = ReadIni(INI, "MYSQL", "Socket");
   ClientFlag = CLIENT_MULTI_STATEMENTS; 

   // DBに接続する。
   DB = MySqlConnect(Host, User, Password, Database, Port, Socket, ClientFlag);
 
   if (DB == -1) {
      Print ("エラー　データベース接続失敗: "+MySqlErrorDescription);
      rtnFlag = -1;
   }
   else {
      //
      //BID/ASKをpricetableテーブルに登録する処理。
      //
       	   string Query = "INSERT INTO `pricetable` (company, currPair, intTimeFrame, Ask, Bid, updateTime) VALUES ("+ "\'" +
                  company + "\', '" +                 	//業者ID
                  currPair + "\', " +                 	//通貨ペア
            	IntegerToString(timeframe) + ", " +	//タイムフレーム
            	DoubleToStr(MarketInfo(currPair,MODE_BID)) + ", " +  //BID
            	DoubleToStr(MarketInfo(currPair,MODE_ASK)) + ", " +     //ASK
            	IntegerToString(TimeLocal()) +     //登録時の時間
              ")";
            //SQL文を実行
       	   if (MySqlExecute(DB, Query) == true) {
              //SQL文実行成功時は、何もしない
           }
           else {
               Print("エラー　データの追加失敗: "+ MySqlErrorDescription);
               Print("エラー　データの追加失敗時のSQL: " + Query);
               rtnFlag = -1;
           }   

      //
      //古いBID/ASKをpricetableテーブルから削除する処理。
      //IntegerToString(timeframe) - DROP_OLD_BEFORE以前に登録されたデータを削除する。
      //
       	  Query = "delete from pricetable where " + "currPair = \'" + currPair + "\' and " +
               "updateTime < " + IntegerToString(TimeLocal() - DROP_OLD_BEFORE);     
           if (MySqlExecute(DB, Query) == true) {
              //SQL文実行成功時は、何もしない
           }
           else {
              Print ("エラー　削除失敗: "+MySqlErrorDescription);
              rtnFlag = -1;
           }

      //            
      //登録済みBID/ASK値のうち、直近の値を取得する。
      //            
      Query = "select company, currPair, intTimeFrame, updateTime, Bid, Ask, max(updatetime) as max_updatetime from pricetable " + " group by company";
      int intCursor = MySqlCursorOpen(DB, Query);
      int bufRows = MySqlCursorRows(intCursor);
      for(int ii = 0; ii < bufRows; ii++)  {
         if (MySqlCursorFetchRow(intCursor) == true){      
            string cursol_comany = MySqlGetFieldAsString(intCursor, 0);
            string cursol_currPair = MySqlGetFieldAsString(intCursor, 1);
            double cursol_Bid = MySqlGetFieldAsDouble(intCursor, 4);
            double cursol_Ask = MySqlGetFieldAsDouble(intCursor, 5);
            datetime cursol_max_updatetime = MySqlGetFieldAsDatetime(intCursor, 6);
            //
            //
            //ここに、各社の各社のBID/ASKを配列に保存手続きを記載する。
            //事故防止のため、配列に保存するロジックは、省略した。
            //
            //
         }
      }

    //
    //
    //ここに、各社のBID/ASKを比較するなどして、発注先、発注内容（新規建て、決済など）を判断するためのロジックを記載する。
    //事故防止のため、発注ロジックは、省略した。
    //
    //
    //ここに、複数MT4間で発注の成功/失敗、発注時間やロット管理をするためのロジックを記載する。
    //
    //
   }      

   //DBとの接続を切断
   MySqlDisconnect(DB);
   
   return rtnFlag;
}




