//+------------------------------------------------------------------+	
//| 　　                                       Puella_ManageRate.mq4 |	
//|    Copyright (c) 2019 トラの親(tora_no_oya) All rights reserved. |	
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
//extern int DROP_OLD_BEFORE 100;  //ローカル時間TimeLocal()より、この値だけ以前のデータを削除する。負を設定すると100に変換。
extern string DataFileName = ""; // /MQL4/Filesまたは/MQL4/tester/Files

//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
struct st_pricetable{ 
   string company;   //company:String   FXTF-demoなど
   string currPair;  //currPair:String   USDJPY-cdなど
   int intTimeFrame;  //intTimeFrame: PERIOD_M1 = 1 = 1分、PERIOD_M5 = 5 = 5分等。
   double Bid;       //Bid
   double Ask;       //Ask
   int updateTime;   //更新時間
};

st_pricetable pricetable_rows[100];
int pricetable_cols = 6;


//+------------------------------------------------------------------+	
//| 初期処理                                                         |	
//+------------------------------------------------------------------+	
int init()	
{	
  DataFileName = "pricetable.csv"; // /MQL4/Filesまたは/MQL4/tester/Files
 //DataFileName = "f:\\pricetable.csv"; // /MQL4/Filesまたは/MQL4/tester/Files
// DataFileName = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\hoge.txt";
 int fileHandle = FileOpen(DataFileName, FILE_SHARE_WRITE|FILE_COMMON ,",");
    if(fileHandle != INVALID_HANDLE){
      //省略
      Print("ファイル開いた");
    }
   else {
      printf( "[%d]ファイルオープンエラー：%s" , __LINE__ , DataFileName);
      Print(GetLastError());
   }    
         FileClose(fileHandle);

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
 int fileHandle = FileOpen(DataFileName, FILE_CSV|FILE_WRITE|FILE_COMMON ,",");

    if(fileHandle != INVALID_HANDLE){
      //省略
      Print("ファイル開いた");
    }
   else {
      printf( "[%d]ファイルオープンエラー：%s" , __LINE__ , DataFileName);
      Print(GetLastError());
   }    
         FileClose(fileHandle);

    return(0);	
   string currPair  = Symbol();
   datetime timeframe = Period();
   string company = AccountServer();
   updatePrice(company, currPair, timeframe);
return 0;
}


//+------------------------------------------------------------------+
//| 自作関数                                                         |	
//+------------------------------------------------------------------+	
//ファイルに、ASK, BID, 書き込み時間等を登録する。        
//ファイル構造定義は、次のとおり。
//ファイル名：pricetable.csv
//company:String   FXTF-demoなど
//currPair:String   USDJPY-cdなど
//intTimeFrame: PERIOD_M1 = 1 = 1分、PERIOD_M5 = 5 = 5分等。
//Bid:double
//Ask:double
//updateTime:int = datetime   
//入力：company = サーバ名, currPair = 通貨ペア, timeframe = タイムフレーム
//返り値： 正常終了は、更新後のデータ件数。失敗は、-1。
int updatePrice(string company, string currPair, datetime timeframe)  {
   int i = 0;
   int rtnFlag = 0;  //正常終了時の返り値0を設定する。

   //入力値チェック
   //なし

   //
   //データファイルを読み込む
   //
   int fileHandle = FileOpen(DataFileName, FILE_SHARE_READ |FILE_SHARE_WRITE |FILE_COMMON ,",");

Print("共通ディレクトリ>>>"+DataFileName);

   // ファイルを正しく読み込めたか？
   if(fileHandle != INVALID_HANDLE){
      // ファイルが最終行に達していない間はループ
      while(FileIsEnding(fileHandle) == false){
         // 1行読み込んで文字列rowに格納
         string row = FileReadString(fileHandle);
         // 実現したい処理をここに記述

         string split_str[];
         int split_num = StringSplit(row , ',' , split_str);

         //カンマ区切りで、pricetable_colsアイテムある行のみ、変数に保存。
         if(split_num == pricetable_cols - 1) {    
            pricetable_rows[i].company = split_str[0];
            pricetable_rows[i].currPair = split_str[1];
            pricetable_rows[i].intTimeFrame = split_str[2];
            pricetable_rows[i].Bid = split_str[3];
            pricetable_rows[i].Ask = split_str[4];
            pricetable_rows[i].updateTime = split_str[5];
            i++;
         }
      }
      FileClose(fileHandle);
      
   }
   else {
      printf( "[%d]ファイルオープンエラー：%s" , __LINE__ , DataFileName);
      Print(GetLastError());
   }

   
   int pricetable_rows_number = 0;
   if(i > 1) {
      pricetable_rows_number = i -1;
   };  //ファイルから正しく読み込み、格納した配列の個数

   //
   //メモリ上のデータを更新する
   //
   //更新対象データを含む配列を探す。
   bool findFlag = false;
   bool foundIndex = -1;
   for( i = 0; i < pricetable_rows_number; i++) {
      if( (StringCompare(pricetable_rows[i].company, company) == true) 
       && (StringCompare(pricetable_rows[i].currPair, currPair) == true ) 
       && (StringCompare(pricetable_rows[i].intTimeFrame, timeframe) == true ) ) {
         findFlag = true;
         foundIndex = i;
         break; 
      }
   }

   //更新対象データを含む配列が見つかった場合
   if(findFlag == true) {
      pricetable_rows[foundIndex].company = company;
      pricetable_rows[foundIndex].currPair = currPair;
      pricetable_rows[foundIndex].intTimeFrame = timeframe;
      pricetable_rows[foundIndex].Bid = MarketInfo(currPair,MODE_BID);
      pricetable_rows[foundIndex].Ask = MarketInfo(currPair,MODE_ASK);
      pricetable_rows[foundIndex].updateTime = TimeLocal();
   }
   //更新対象データを含む配列が見つからなかった場合＝末尾に追加
   else {
      pricetable_rows[pricetable_rows_number].company = company;
      pricetable_rows[pricetable_rows_number].currPair = currPair;
      pricetable_rows[pricetable_rows_number].intTimeFrame = timeframe;
      pricetable_rows[pricetable_rows_number].Bid = MarketInfo(currPair,MODE_BID);
      pricetable_rows[pricetable_rows_number].Ask = MarketInfo(currPair,MODE_ASK);
      pricetable_rows[pricetable_rows_number].updateTime = TimeLocal();
      pricetable_rows_number = pricetable_rows_number + 1;
   }


   //
   //データファイルを書き込む
   //
   // 書き込むファイルを開く(存在しなければ作成される)
   fileHandle = FileOpen(DataFileName,    // ファイル名
                         FILE_SHARE_READ |FILE_SHARE_WRITE |FILE_COMMON,  // ファイル操作モードフラグ
                         ','                     // セパレート文字コード
                );

   if(fileHandle != INVALID_HANDLE){
      for(i = 0; i < pricetable_rows_number; i++) {
         FileWrite(fileHandle , 
                   pricetable_rows[i].company ,
                   pricetable_rows[i].currPair ,
                   pricetable_rows[i].intTimeFrame ,
                   pricetable_rows[i].Bid ,
                   pricetable_rows[i].Ask ,
                   pricetable_rows[i].updateTime);
      }
      FileClose(fileHandle);
   }
   else {
      printf( "[%d]ファイルオープンエラー：%s" , __LINE__ , DataFileName);
      rtnFlag = -1;
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
 


   return pricetable_rows_number;
}





