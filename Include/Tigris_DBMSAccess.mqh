// 20220416 DBMSアクセス用の変数、関数をまとめた

//+------------------------------------------------------------------+	
//| ヘッダーファイル読込                                                     |	
//+------------------------------------------------------------------+	
#include <MQLMySQL.mqh>

//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
string INI;
string Host;
string User;
string Password;
string Database;
string Socket;   // database credentials
int    Port;
int    ClientFlag;
int    DB;        // database identifier
//+------------------------------------------------------------------+	
//| 外部パラメーター宣言                                             |	
//+------------------------------------------------------------------+	

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|   共通関数                                                    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| DBに接続する。                                                   |
//| 接続に失敗した時、falseを返す。                                  |
//+------------------------------------------------------------------+
bool DB_initial_Connect2DB() {
   // C:\Program Files (x86)\FXTF MT4_20201001\MQL4\scripts
   INI = TerminalInfoString(TERMINAL_PATH)+"\\MQL4\\Scripts\\MyConnection.ini";
 
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
   if(DB == -1) {
      printf( "[%d]エラー　DB接続失敗:%s" , __LINE__, MySqlErrorDescription);
      return false;
   }

   return true;
}





