#property copyright "Copyright 2019, toranooya."
#property link      "https://nenshuuha.blog.fc2.com/"
#property version   "1.00"
#property strict

#include <MQLMySQL.mqh>
#include <MQLMySQL.mqh>
 
string INI;
datetime mySTARTTIME; //DBにデータを出力する最初の時間。Datetime(int)型。
datetime myENDTIME;   //DBにデータを出力する最後の時間。Datetime(int)型。

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
 
   mySTARTTIME = StrToTime("2010/01/01 0:00");
   myENDTIME   = StrToTime("2019/12/17 23:59");

   string currPair  = Symbol();
   int timeframe = Period();
   datetime startTime = mySTARTTIME; //処理開始日の定義と初期値
   datetime endTime   = myENDTIME;   //処理終了日の定義と初期値

   //
   // ヒストリーセンターでエクスポートしたCSVファイルをpuerdb.pariceにインポートする。
   // CSVファイルに含まれる通貨ペア、時間軸はプログラムで渡す。
  //20211205 EURUSD-15インポート済み importCSV();
   
   
   
   //
   //
   /*登録済みデータを削除後、2019/01/01 0:00から2020/01/09 23:00のデータを登録する処理*/
   //
   /*
   startTime = StrToTime("2010/01/01 0:00") ;
   endTime   = StrToTime("2020/01/09 23:00");   
   delete_and_insertAllPrice(currPair, timeframe, startTime, endTime );
   */
   
   //
   /*2019/01/01 0:00から2020/01/09 23:00のデータを登録する処理*/
   //
   /*
   startTime = StrToTime("2010.12.08 22:44") ;
   endTime   = StrToTime("2021/12/04 23:00");
   updatePrice(currPair, timeframe, startTime, endTime );
   */

//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   
  }
//+------------------------------------------------------------------+
 
//スクリプト開始



//
// ヒストリーセンターでエクスポートしたCSVファイルをpuerdb.pariceにインポートする。
// CSVファイルに含まれる通貨ペア、時間軸はプログラムで渡す。
bool importCSV() {
   int timeframe = Period();
   string currPair = "EURUSD-cd";
   string fileName = "./csv/EURUSD-cd15.csv";
   bool errFlag = true;
   
   int handle = FileOpen(fileName, FILE_READ|FILE_CSV, ",");
   if (handle < 0)
   {
      printf( "[%d]エラー  ファイルオープン失敗。" , __LINE__);
      return false;
   }

   //
   //DBに接続する。
   //
   string Host, User, Password, Database, Socket; // database credentials
   int Port,ClientFlag;
   int DB; // database identifier
 
   INI = TerminalInfoString(TERMINAL_PATH)+"\\MQL4\\Scripts\\MyConnection.ini";
 
   // INIファイルから、DB接続情報を取得する。
   Host = ReadIni(INI, "MYSQL", "Host");
   User = ReadIni(INI, "MYSQL", "User");
   Password = ReadIni(INI, "MYSQL", "Password");
   Database = ReadIni(INI, "MYSQL", "Database");
   Port 	= (int)StringToInteger(ReadIni(INI, "MYSQL", "Port"));
   Socket   = ReadIni(INI, "MYSQL", "Socket");
   ClientFlag = CLIENT_MULTI_STATEMENTS;
 
// DBに接続する。
   DB = MySqlConnect(Host, User, Password, Database, Port, Socket, ClientFlag);
 
   if (DB == -1) {
      printf( "[%d]エラー　接続失敗:%s" , __LINE__, MySqlErrorDescription);      
      errFlag = false;
   }

   

   string bufDate = "";
   string bufTime = "";
   string bufDateTime_string = "";
   datetime bufDateTime_datetime = 0;
   string bufOpen = "";
   string bufHigh = "";
   string bufLow = "";
   string bufClose = "";
   string bufNum = "";

   string Query = "delete from pricetable where " +
                  "currPair = \'" + currPair + "\' and " +
                  "intTimeFrame = " + IntegerToString(timeframe);
   if(errFlag == true) { 
      //SQL文を実行
      if (MySqlExecute(DB, Query) == true) {
     	}
      else {
         printf( "[%d]エラー　削除失敗:%s" , __LINE__, MySqlErrorDescription);              
         printf( "[%d]エラー　追加失敗時のSQL:%s" , __LINE__, Query);
         errFlag = false;   
      }   
                
      while(errFlag == true && FileIsEnding(handle) == false) {
         bufDate = FileReadString(handle);
         bufTime = FileReadString(handle);
         bufDateTime_string   = bufDate + " " + bufTime;
         bufDateTime_datetime = StrToTime(bufDateTime_string);
         bufOpen = FileReadString(handle);
         bufHigh = FileReadString(handle);
         bufLow = FileReadString(handle);
         bufClose = FileReadString(handle);
         bufNum = FileReadString(handle);
               
   //      bufDateTime = StrToTime(bufDate); 
   /*
         printf( "[%d]テスト 日時=%s Open=%s Hight=%s Low=%s Close=%s" , __LINE__, 
                  TimeToStr(StrToTime(bufDate + " " + bufTime))
                  , DoubleToStr(StrToDouble(bufOpen))
                  , DoubleToStr(StrToDouble(bufHigh))
                  , DoubleToStr(StrToDouble(bufLow))
                  , DoubleToStr(StrToDouble(bufClose))                                             
                  
                  );
         
    */
               
         Query = "INSERT INTO `pricetable` (currPair, intTimeFrame, intTime, strTime, Open, High, Low, Close) VALUES ("+ "\'" +
               currPair + "\', " +                 	//通貨ペア
            	IntegerToString(timeframe) + ", " +	   //タイムフレーム
            	IntegerToString(bufDateTime_datetime) + ", \'" + 	//時間。整数値
            	TimeToStr(bufDateTime_datetime) + "\', " +       	//時間。文字列
            	bufOpen + ", " +                   	//始値
            	bufHigh + ", " +                   	//高値
            	bufLow + ", " +                    	//安値
            	bufClose  +                  	//終値
              ")";
         //SQL文を実行
       	if (MySqlExecute(DB, Query) == true) {
         }
         else {
            printf( "[%d]エラー　追加失敗:%s" , __LINE__, MySqlErrorDescription);              
            printf( "[%d]エラー　追加失敗時のSQL:%s" , __LINE__, Query);              
            errFlag = false;
         }
      }
   }
   //DBとの接続を切断
   MySqlDisconnect(DB);
   
   FileClose(handle);

   if(errFlag == true) {
      return true;
   }
   else {
      return false;
   }
   
}





//通貨ペア名とタイムフレームをキーとしてpricetableに、登録開始日時startTimeから登録終了日時endTimeまでのデータを登録する。
//
//【注意】通貨ペア名とタイムフレームをキーとしてpricetableを検索して、登録済みのデータがあれば、削除する。
//
//入力：通貨ペアcurrPair, タイムフレームtimeframe
//返り値： 登録成功時は、0。失敗は、-1。
int delete_and_insertAllPrice(string currPair, int timeframe, datetime startTime, datetime endTime){
   datetime maxIntTime = 0;
   datetime minIntTime = 0;
   datetime defaultIntStartTime = StringToTime("2010/1/1 0:00"); 

   int rtnFlag = -1; 

   //入力値チェック
   if(startTime > endTime) {
      rtnFlag = -1;
      printf( "[%d]エラー  エラー　引数の異常:開始時間 > 終了時間" , __LINE__);
      return rtnFlag;
   }
   
   //
   //DBに接続する。
   //
   string Host, User, Password, Database, Socket; // database credentials
   int Port,ClientFlag;
   int DB; // database identifier
   string strBuf ;
 
   INI = TerminalInfoString(TERMINAL_PATH)+"\\MQL4\\Scripts\\MyConnection.ini";
 
   // INIファイルから、DB接続情報を取得する。
   Host = ReadIni(INI, "MYSQL", "Host");
   User = ReadIni(INI, "MYSQL", "User");
   Password = ReadIni(INI, "MYSQL", "Password");
   Database = ReadIni(INI, "MYSQL", "Database");
printf( "[%d]テスト　接続先DB:%s" , __LINE__, INI);      
   
   Port 	= (int)StringToInteger(ReadIni(INI, "MYSQL", "Port"));
   Socket   = ReadIni(INI, "MYSQL", "Socket");
   ClientFlag = CLIENT_MULTI_STATEMENTS;
   //Print ("Host: ",Host, ", User: ", User, ", Database: ",Database);
 
// DBに接続する。
   DB = MySqlConnect(Host, User, Password, Database, Port, Socket, ClientFlag);
 
   if (DB == -1) {
      printf( "[%d]エラー　接続失敗:%s" , __LINE__, MySqlErrorDescription);      
      rtnFlag = -1;
      return rtnFlag;
   }
   else {
      //登録済みデータを削除する。
      int delflag = deletePrice(currPair, timeframe);

      //チャートのサイズ
      int size = ArraySize(Time);
      //過去から出力
      for(int i = size - 1; i >= 0; i--){
      	//期間の範囲外は、以降の処理を飛ばす。
      	if(Time[i] < startTime || endTime < Time[i]){
          	continue;
      	}
       	
        	//1件をDBに登録する。
         //Table名：pricetable
        	//currPair:String   USDJPY-cdなど
        	//intTimeFrame: PERIOD_M1 = 1 = 1分、PERIOD_M5 = 5 = 5分等。
        	//intTime:datetime型＝整数値
        	//strTime:文字列型　＝　yyyy/mm/dd hh:mm:ss  2019:12:13 14:54
         //Open:double
         //High:double
         //Low:double
         //Close:double
    	   string Query = "INSERT INTO `pricetable` (currPair, intTimeFrame, intTime, strTime, Open, High, Low, Close) VALUES ("+ "\'" +
         Symbol() + "\', " +                 	//通貨ペア
         	IntegerToString(timeframe) + ", " +	//タイムフレーム
         	IntegerToString(iTime(currPair, timeframe, i)) + ", \'" + 	//時間。整数値
         	TimeToStr(iTime(currPair, timeframe, i)) + "\', " +       	//時間。文字列
         	DoubleToStr(iOpen(currPair, timeframe, i)) + ", " +                   	//始値
         	DoubleToStr(iHigh(currPair, timeframe, i)) + ", " +                   	//高値
         	DoubleToStr(iLow(currPair, timeframe, i)) + ", " +                    	//安値
         	DoubleToStr(iClose(currPair, timeframe, i))  +                  	//終値
           ")";
         //SQL文を実行
    	   if (MySqlExecute(DB, Query) == true) {
        	   rtnFlag = 0;
        	}
       	 else {
            rtnFlag = -1;
            printf( "[%d]エラー　追加失敗:%s" , __LINE__, MySqlErrorDescription);              
            printf( "[%d]エラー　追加失敗時のSQL:%s" , __LINE__, Query);              
            
            break;
          }
      } //forの終わり
   }
   
   
   //DBとの接続を切断
   MySqlDisconnect(DB);
   /*
   if(rtnFlag < 0) {
      deletePrice(currPair, timeframe);
   }
   */
   
   return rtnFlag;
}



//通貨ペア名とタイムフレームをキーとしてpricetableに、登録開始日時startTimeから登録終了日時endTimeまでのデータを登録する。
//ただし、通貨ペア名とタイムフレームをキーとしてpricetableを検索して、
//  1) 入力キーのデータが無ければ、。登録開始日時startTimeから登録終了日時endTimeを登録する。＝insertPrice(currPair, timeframe,startTime, endTime)
//  2) 入力キーのデータがあれば、されに場合分けする。
//    2)-1 登録開始日時startTimeが登録済データの最小日付以下かつ登録終了日時が最大日付以上の時、
//         つまり、「追加しようとする期間が、既存データの期間を完全に包含している場合は、
//         登録済みデータを削除後、対象期間のデータを追加する。
//           → deletePrice(currPair, timeframe); →　insertPrice(currPair, timeframe,登録開始日時, 登録終了日時)
//    2)-2 登録開始日時startTimeが登録済データの最小日付以上かつ登録終了日時が最大日付以下の時、
//         つまり、「追加しようとする期間が、既存データの期間に完全に包含されている場合は、追加、削除はしない。
//    2)-3 上記のいずれでもなく、登録開始日時startTimeが登録済データの最小日付 - 1以下かつ登録終了日時が最大日付　- 1以下の時、
//         つまり、「追加しようとする期間のうち、登録開始時間から登録済データの最小日付 - 1が未登録のため、新規追加
//           → insertPrice(currPair, timeframe,登録開始日時, 最小日付 - 1)
//    2)-4 上記のいずれでもなく、登録開始日時startTimeが登録済データの最小日付 + 1以上かつ登録終了日時が最大日付 + 1以上の時、
//         つまり、「追加しようとする期間のうち、登録済データの最大日付 + 1から 登録終了日時がが未登録のため、新規追加
//           → insertPrice(currPair, timeframe,最大日付 + 1, 登録終了日時)//           
//入力：通貨ペアcurrPair, タイムフレームtimeframe
//返り値： 登録成功時は、0。失敗は、-1。
int updatePrice(string currPair, datetime timeframe, datetime startTime, datetime endTime){
   datetime maxIntTime = 0;
   datetime minIntTime = 0;
   datetime defaultIntStartTime = StringToTime("2010/1/1 0:00"); 

   int rtnFlag = -1; 

   //入力値チェック
   if(startTime > endTime) {
      rtnFlag = -1;
      printf( "[%d]エラー　引数の異常:開始時間 > 終了時間" , __LINE__);              
      return rtnFlag;
   }
   
   //
   //DBに接続する。
   //
   string Host, User, Password, Database, Socket; // database credentials
   int Port,ClientFlag;
   int DB; // database identifier
   string strBuf ;
 
   INI = TerminalInfoString(TERMINAL_PATH)+"\\MQL4\\Scripts\\MyConnection.ini";
 
   // INIファイルから、DB接続情報を取得する。
   Host = ReadIni(INI, "MYSQL", "Host");
   User = ReadIni(INI, "MYSQL", "User");
   Password = ReadIni(INI, "MYSQL", "Password");
   Database = ReadIni(INI, "MYSQL", "Database");
   Port 	= (int)StringToInteger(ReadIni(INI, "MYSQL", "Port"));
   Socket   = ReadIni(INI, "MYSQL", "Socket");
   ClientFlag = CLIENT_MULTI_STATEMENTS;
   //Print ("Host: ",Host, ", User: ", User, ", Database: ",Database);
 
// DBに接続する。
   DB = MySqlConnect(Host, User, Password, Database, Port, Socket, ClientFlag);
 
   if (DB == -1) {
      printf( "[%d]エラー　接続失敗:%s" , __LINE__, MySqlErrorDescription);              
      
      rtnFlag = -1;
      return rtnFlag;
   }
   else {
      //テーブルに、通貨ペア名とタイムフレームをキーとしたデータが残っていれば、
      //その最初の時間min(intTime)、最後の時間max(intTime)を取得する。
      strBuf = "select count(*), min(intTime), max(intTime) from pricetable where " +
               "currPair = \'" + currPair + "\' and " +
               "intTimeFrame = " + IntegerToString(timeframe);
      int intCursor = MySqlCursorOpen(DB, strBuf);
   
      //カーソルの取得失敗時は後続処理をしない。
      if(intCursor < 0) {
         rtnFlag = -1;
         printf( "[%d]エラー　追カーソルオープン失敗:%s" , __LINE__, MySqlErrorDescription);              
         
      }
      else {
         //カーソルの指す1件を取得する。
         bool cursolFlag = MySqlCursorFetchRow(intCursor);
         if(cursolFlag == false) {
            rtnFlag = -1;
            printf( "[%d]エラー　登録済みデータあり:%s" , __LINE__, MySqlErrorDescription);              

         }
         else {
            int registerdRows = MySqlGetFieldAsInt(intCursor, 0);
            minIntTime        = MySqlGetFieldAsInt(intCursor, 1);
            maxIntTime        = MySqlGetFieldAsInt(intCursor, 2);
                        
            if(registerdRows <= 0) {
               rtnFlag = -1;
            }
            
            //
            //登録開始日時startTime及び登録終了日時endTimeの更新
            //            
            
            //  1) 入力キーのデータが無ければ、。登録開始日時startTimeから登録終了日時endTimeのデータをを登録する。
            if(registerdRows <= 0) {
               // 登録開始日時startTime及び登録終了日時endTimeの更新は無し。
               //　登録処理実施のため、rtnFlagを0とする。
               rtnFlag = 0;
            }
            //    2)-1 登録開始日時startTimeが登録済データの最小日付以下かつ登録終了日時が最大日付以上の時、
            //         つまり、「追加しようとする期間が、既存データの期間を完全に包含している場合は、
            //         登録済みデータを削除後、対象期間のデータを追加する。
            //           → deletePrice(currPair, timeframe); →　insertPrice(currPair, timeframe,登録開始日時, 登録終了日時)            
            else if( startTime <= minIntTime && endTime >= maxIntTime) {
               //登録済みデータの削除
               int flag2_1 = deletePrice(currPair, timeframe);
               
               // 登録開始日時startTime及び登録終了日時endTimeの更新は無し。
               
               // 削除処理が失敗していれば、後続処理を中止。
               //　それ以外は、登録処理実施のため、rtnFlagを1とする。
               if(flag2_1 < 0) {
                  rtnFlag = -1;
               }
               else {
                  //　登録処理実施のため、rtnFlagを1とする。
                  rtnFlag = 0;
               }
            }
            //    2)-2 登録開始日時startTimeが登録済データの最小日付以上かつ登録終了日時が最大日付以下の時、
            //         つまり、「追加しようとする期間が、既存データの期間に完全に包含されている場合は、追加、削除はしない。            
            else if(startTime >= minIntTime && endTime <= maxIntTime) {
               //登録処理をしない。
               rtnFlag = -1;
            }
            //    2)-3 上記のいずれでもなく、登録開始日時startTimeが登録済データの最小日付 - 1以下かつ登録終了日時が最大日付　- 1以下の時、
            //         つまり、「追加しようとする期間のうち、登録開始時間から登録済データの最小日付 - 1が未登録のため、新規追加
            //           → insertPrice(currPair, timeframe,登録開始日時, 最小日付 - 1)
            else if(startTime <= (minIntTime - 1) && (endTime <= maxIntTime - 1)) {
               // 登録開始日時startTimeの更新は無し。
               // 登録終了日時endTimeは、 登録済データの最小日付 - 1とする
               endTime = minIntTime - 1;

               //　登録処理実施のため、rtnFlagを0とする。
               rtnFlag = 0;
            }
            //    2)-4 上記のいずれでもなく、登録開始日時startTimeが登録済データの最小日付 + 1以上かつ登録終了日時が最大日付 + 1以上の時、
            //         つまり、「追加しようとする期間のうち、登録済データの最大日付 + 1から 登録終了日時が未登録のため、新規追加               
            else if(startTime >= (minIntTime + 1) && endTime >= (maxIntTime + 1) ) {
               // 登録開始日時startTimeは、登録データの最大日付 + 1。
                  startTime = maxIntTime + 1;
               // 登録終了日時endTimeの更新は無し。

               //　登録処理実施のため、rtnFlagを0とする。
               rtnFlag = 0;
            }
            else {
               //想定していないケースが発生したため、エラー処理
               printf( "[%d]エラー　想定外の組み合わせの日付が、発生:%s" , __LINE__, MySqlErrorDescription);              
               
               rtnFlag = -1;
            }

            // 登録開始日付及び登録終了日付が逆転していれば、後続処理をしない。
            if(startTime > endTime) {
               rtnFlag = -1;
               printf( "[%d]エラー　登録開始日付及び登録終了日付が逆転:%s" , __LINE__, MySqlErrorDescription);              
               
            }               
            

            
            //この行までに、登録開始日時startTime及び登録終了日時endTimeの更新
            //及び登録されていたデータの削除を行う。
            //途中の処理でrtnFlagが0になっていなければ、insert文を実行しない。
            if(rtnFlag >= 0) {
               //チャートのサイズ
               int size = ArraySize(Time);
               //過去から出力
               for(int i = size - 1; i >= 0; i--){
               	//期間の範囲外は、以降の処理を飛ばす。
               	if(Time[i] < startTime || endTime < Time[i]){
                   	continue;
               	}
                	
                 	//1件をDBに登録する。
                  //Table名：pricetable
                 	//currPair:String   USDJPY-cdなど
                 	//intTimeFrame: PERIOD_M1 = 1 = 1分、PERIOD_M5 = 5 = 5分等。
                 	//intTime:datetime型＝整数値
                 	//strTime:文字列型　＝　yyyy/mm/dd hh:mm:ss  2019:12:13 14:54
                  //Open:double
                  //High:double
                  //Low:double
                  //Close:double
             	   string Query = "INSERT INTO `pricetable` (currPair, intTimeFrame, intTime, strTime, Open, High, Low, Close) VALUES ("+ "\'" +
                  Symbol() + "\', " +                 	//通貨ペア
                  	IntegerToString(Period()) + ", " +	//タイムフレーム
                  	IntegerToString(Time[i]) + ", \'" + 	//時間。整数値
                  	TimeToStr(Time[i]) + "\', " +       	//時間。文字列
                  	DoubleToStr(Open[i]) + ", " +                   	//始値
                  	DoubleToStr(High[i]) + ", " +                   	//高値
                  	DoubleToStr(Low[i]) + ", " +                    	//安値
                  	DoubleToStr(Close[i])  +                  	//終値
                    ")";
                  //SQL文を実行
             	   if (MySqlExecute(DB, Query) == true) {
                 	   rtnFlag = 0;
                 	}
                	 else {
                     rtnFlag = -1;
                     printf( "[%d]エラー　データの追加失敗:%s" , __LINE__, MySqlErrorDescription);                                   
                     printf( "[%d]エラー　追加失敗時のSQL:%s" , __LINE__, Query);                                   
                     
                     break;
                     
                   }
               } //forの終わり
            }
         }     
      }   
   }
   
   
   //DBとの接続を切断
   MySqlDisconnect(DB);
   /*
   if(rtnFlag < 0) {
      deletePrice(currPair, timeframe);
   }
   */
   
   return rtnFlag;
}



//通貨ペア名とタイムフレームをキーとしてpricetableに、mySTARTTIMEから指定時間までのデータを登録する。
//ただし、通貨ペア名とタイムフレームをキーとしてpricetableを検索して、該当データがあれば、処理を失敗とする。
//入力：通貨ペアcurrPair, タイムフレームtimeframe
//返り値： 登録成功時は、0。失敗は、-1。
int insertPrice(string currPair, datetime timeframe, datetime endTime){
   datetime maxIntTime = 0;
   datetime minIntTime = 0;
   datetime defaultIntStartTime = StringToTime("2010/1/1 0:00"); 

   int rtnFlag = -1; 
   //
   //DBに接続する。
   //
   string Host, User, Password, Database, Socket; // database credentials
   int Port,ClientFlag;
   int DB; // database identifier
   string strBuf ;
 
   INI = TerminalInfoString(TERMINAL_PATH)+"\\MQL4\\Scripts\\MyConnection.ini";
 
   // INIファイルから、DB接続情報を取得する。
   Host = ReadIni(INI, "MYSQL", "Host");
   User = ReadIni(INI, "MYSQL", "User");
   Password = ReadIni(INI, "MYSQL", "Password");
   Database = ReadIni(INI, "MYSQL", "Database");
   Port 	= (int)StringToInteger(ReadIni(INI, "MYSQL", "Port"));
   Socket   = ReadIni(INI, "MYSQL", "Socket");
   ClientFlag = CLIENT_MULTI_STATEMENTS;
   //Print ("Host: ",Host, ", User: ", User, ", Database: ",Database);
 
// DBに接続する。
   DB = MySqlConnect(Host, User, Password, Database, Port, Socket, ClientFlag);
 
   if (DB == -1) {
      printf( "[%d]エラー　接続失敗:%s" , __LINE__, MySqlErrorDescription);          
      rtnFlag = -1;
      return rtnFlag;
   }
   else {
      //テーブルに、通貨ペア名とタイムフレームをキーとしたデータが残っていれば、作業失敗とする。
      strBuf = "select count(*) from pricetable where " +
               "currPair = \'" + currPair + "\' and " +
               "intTimeFrame = " + IntegerToString(timeframe);
   
      int intCursor = MySqlCursorOpen(DB, strBuf);
   
      //最遅の登録済みデータの時間が返っている場合のみ、抽出開始日時を更新する。
      if(intCursor < 0) {
         rtnFlag = -1;
         printf( "[%d]エラー　カーソルオープン失敗:%s" , __LINE__, MySqlErrorDescription);             
      }
      else {
         //カーソルの指す1件を取得する。
         bool cursolFlag = MySqlCursorFetchRow(intCursor);
         if(cursolFlag == false) {
            rtnFlag = -1;
            printf( "[%d]エラー　登録済みデータあり:%s" , __LINE__, MySqlErrorDescription);    
         }
         else {
            int registerdRows = MySqlGetFieldAsInt(intCursor, 0);
            
            //該当データが存在しない場合のみ、後続処理を行う。
            if(registerdRows > 0) {
               rtnFlag = -1;
            }
            else {
               //チャートのサイズ
               int size = ArraySize(Time);
               //過去から出力
               for(int i = size - 1; i >= 0; i--){
               	//期間の範囲外は、以降の処理を飛ばす。
               	if(Time[i] < mySTARTTIME || endTime <= Time[i]){
                   	continue;
               	}
                	
                 	//1件をDBに登録する。
                  //Table名：pricetable
                 	//currPair:String   USDJPY-cdなど
                 	//intTimeFrame: PERIOD_M1 = 1 = 1分、PERIOD_M5 = 5 = 5分等。
                 	//intTime:datetime型＝整数値
                 	//strTime:文字列型　＝　yyyy/mm/dd hh:mm:ss  2019:12:13 14:54
                  //Open:double
                  //High:double
                  //Low:double
                  //Close:double
             	   string Query = "INSERT INTO `pricetable` (currPair, intTimeFrame, intTime, strTime, Open, High, Low, Close) VALUES ("+ "\'" +
                  Symbol() + "\', " +                 	//通貨ペア
                  	IntegerToString(Period()) + ", " +	//タイムフレーム
                  	IntegerToString(Time[i]) + ", \'" + 	//時間。整数値
                  	TimeToStr(Time[i]) + "\', " +       	//時間。文字列
                  	DoubleToStr(Open[i]) + ", " +                   	//始値
                  	DoubleToStr(High[i]) + ", " +                   	//高値
                  	DoubleToStr(Low[i]) + ", " +                    	//安値
                  	DoubleToStr(Close[i])  +                  	//終値
                    ")";
                  //SQL文を実行
             	   if (MySqlExecute(DB, Query) == true) {
                 	   rtnFlag = 0;
                 	}
                	 else {
                     rtnFlag = -1;
                     printf( "[%d]エラー　データの追加失敗:%s" , __LINE__, MySqlErrorDescription);    
                     printf( "[%d]エラー　追加失敗時のSQL:%s" , __LINE__, Query);    
                     break;
                   }
               } //forの終わり
            }
         }     
      }   
   }
   //DBとの接続を切断
   MySqlDisconnect(DB);
   if(rtnFlag < 0) {
      deletePrice(currPair, timeframe);
   }
   
   return rtnFlag;
}



//通貨ペア名とタイムフレームをキーとしてpricetableからデータを削除する。
//入力：通貨ペアcurrPair, タイムフレームtimeframe
//返り値： 削除成功時は、0。削除失敗は、-1。
int deletePrice(string currPair, datetime timeframe){
   //DBに接続する。
   //
   string Host, User, Password, Database, Socket; // database credentials
   int Port,ClientFlag;
   int DB; // database identifier
   string strBuf ;
   int rtnFlag = -1; 
   INI = TerminalInfoString(TERMINAL_PATH)+"\\MQL4\\Scripts\\MyConnection.ini";
 
   // INIファイルから、DB接続情報を取得する。
   Host = ReadIni(INI, "MYSQL", "Host");
   User = ReadIni(INI, "MYSQL", "User");
   Password = ReadIni(INI, "MYSQL", "Password");
   Database = ReadIni(INI, "MYSQL", "Database");
   Port 	= (int)StringToInteger(ReadIni(INI, "MYSQL", "Port"));
   Socket   = ReadIni(INI, "MYSQL", "Socket");
   ClientFlag = CLIENT_MULTI_STATEMENTS;
   //Print ("Host: ",Host, ", User: ", User, ", Database: ",Database);
 
// DBに接続する。
   DB = MySqlConnect(Host, User, Password, Database, Port, Socket, ClientFlag);
 
   if (DB == -1) {
      printf( "[%d]エラー 接続失敗=%s" , __LINE__ ,MySqlErrorDescription);
      rtnFlag = -1;
   }
   else {
      strBuf = "delete from pricetable where " +
               "currPair = \'" + currPair + "\' and " +
               "intTimeFrame = " + IntegerToString(timeframe);
      printf( "[%d]テスト データを削除するためのSQL文=%s" , __LINE__ ,strBuf);
      
      if (MySqlExecute(DB,strBuf) == true) {
       rtnFlag = 0;
      }
      else {
         printf( "[%d]エラー  削除失敗=%s" , __LINE__ ,MySqlErrorDescription);
         
         rtnFlag = -1;
      }
   }
     
   MySqlDisconnect(DB);
   return rtnFlag;
}


