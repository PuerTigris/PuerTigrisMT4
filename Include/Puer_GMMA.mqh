//#property strict	
//+------------------------------------------------------------------+	
//|  PuerTigrisのorderByCORREL_TIME部品                              |
//|  Copyright (c) 2016 トラの親 All rights reserved.                |	
//|                                                                  |
//+------------------------------------------------------------------+	
//+------------------------------------------------------------------+	
//| ヘッダーファイル読込                                             |	
//+------------------------------------------------------------------+	
#include <Tigris_COMMON.mqh>
#include <Tigris_GLOBALS.mqh>

//+------------------------------------------------------------------+	
//| 定数宣言部                                                       |	
//+------------------------------------------------------------------+	


//+------------------------------------------------------------------+	
//| グローバル変数宣言                                               |	
//+------------------------------------------------------------------+	
/*
double GMMAWidth  = 0.1;// 直前（SHIFT=1）の陽線・陰線が、さらに1つ前（SHIFT=1）の陽線・陰線と比較して、数％以上であれば、取引をする。単位は、％。
double GMMAHigher = 50;	// RSIがこの値以下ならば、取引する						
double GMMALower  = 10; // RSIがこの値以上ならば、取引する。							
int    GMMALimmit = 25; // ロングの場合は、直近の高値、ショートの場合は直近の安値を更新していた場合のみ、取引。単位は本数（＝SHIFT数）
*/
//+------------------------------------------------------------------+
//|10.GMMA                                      　　　　     　      |
//+------------------------------------------------------------------+
int entryGMMA() {
   double tp = 0.0;
   double sl = 0.0;	
   if(GMMAHigher <= GMMALower) {
      return NO_SIGNAL;
   }
   if(GMMALimmit <= 0) {
      return NO_SIGNAL;
   }
   
   int flgBuySELL = NO_SIGNAL;

   flgBuySELL = judgeGMMA();
   
   if(flgBuySELL != NO_SIGNAL) {
      int ticket_num = 0;
      
      //上昇局面gmmaFlag=1であれば買い。ただしRSI>60で買われ過ぎの時は対象外。
      //陽線（本体の1.5%以上）が発生していること。
    	double RSI_9  = iRSI(global_Symbol, 0,  9, PRICE_CLOSE,1);
    	
      double Close_1 =0.0; 
      double Open_1  = 0.0;
      double Close_2 =0.0; 
      double Open_2  = 0.0;
    	
    	// 短期、長期の値が、最後の条件gmmaFlag3までたどり着き、gmmaFlag3=1であれば、ロング
    	// ただし、
    	// ①直近の値上がり幅が、外部パラメータ設定値GMMAWidth(%)以上であること。
    	// ②RSI>60で買われ過ぎの時は対象外。→RSI < GMMAHigher
      // ③現在のASKが、GMMALimmit本前までの最高値を上回っていること。＝直近最高値をブレーク
     
      if( flgBuySELL == BUY_SIGNAL) {
         RSI_9  = iRSI(global_Symbol, 0,  9, PRICE_CLOSE,1);
         if(RSI_9  < GMMAHigher) {
            // Shift=1の陽線が、Shift=2の陽線と比較して、GMMAWidth(%)以上の場合に、買う。
            // 例）GMMAWidth=5の時、Shift=2の陽線（Close-Open）を100とすると、Shift=1の陽線が105以上の時、買う。
            Close_1 = iClose(global_Symbol, 0, 1); 
            Open_1  = iOpen(global_Symbol, 0, 1);
            Close_2 = iClose(global_Symbol, 0, 2); 
            Open_2  = iOpen(global_Symbol, 0, 2);
            double yousen_1 = NormalizeDouble(Close_1 - Open_1, global_Digits);
            double yousen_2 = NormalizeDouble(Close_2 - Open_2, global_Digits);

            if(yousen_2 > 0.0) {
               if((yousen_1 - yousen_2) / yousen_2 *100 > GMMAWidth ) {
                  double lastHighestValue = iHigh(global_Symbol, 0, iHighest(global_Symbol, 0, MODE_HIGH, GMMALimmit, 1));
                  if(lastHighestValue > 0.0 
                     && NormalizeDouble(Ask, global_Digits) > NormalizeDouble(lastHighestValue, global_Digits)) {
                     return BUY_SIGNAL;
                  }
               }               
            }
         }
      }
   
    	// 短期、長期の値が、最後の条件gmmaFlag3までたどり着き、gmmaFlag3=1であればショート
    	// ①直近の値下がり幅が、外部パラメータ設定値GMMAWidth(%)以上であること。
    	// ②RSI<40などで売られ過ぎの時は対象外。→RSI < GMMALower
      // ③現在のBIDが、GMMALimmit本前までの最安値を下回っていること。＝直近最安値をブレーク。
    	
      if( flgBuySELL == SELL_SIGNAL) {
         RSI_9  = iRSI(global_Symbol, 0,  9, PRICE_CLOSE,1);
   
         if(RSI_9 > GMMALower) { 
            // Shift=1の陰線が、Shift=2の陰線と比較して、GMMAWidth(%)以上の場合に、売る
            // 例）GMMAWidth=5の時、Shift=2の陰線（Close-Open）を100とすると、Shift=1の陰線が105以上の時、買う。
            Close_1 = iClose(global_Symbol, 0, 1); 
            Open_1  = iOpen(global_Symbol, 0, 1);
            Close_2 = iClose(global_Symbol, 0, 2); 
            Open_2  = iOpen(global_Symbol, 0, 2);
            double insen_1 = NormalizeDouble(Open_1 - Close_1, global_Digits);
            double insen_2 = NormalizeDouble(Open_2 - Close_2, global_Digits);

            if(insen_2 > 0.0) {
               if((insen_1 - insen_2) / insen_2 * 100 > GMMAWidth )  {
                  double lastLowestValue = iLow(global_Symbol, 0, iLowest(global_Symbol, 0, MODE_LOW, GMMALimmit, 1));
                  if(lastLowestValue > 0.0
                     && NormalizeDouble(Bid, global_Digits) < NormalizeDouble(lastLowestValue, global_Digits)) {
                     return SELL_SIGNAL;           
                  }
               }
         	}
         }
      }
   }
   return NO_SIGNAL;
}

//
// 短期の移動平均群（3, 5, 8, 10, 12, 15）と長期の移動平均群（30, 35, 40, 45, 50, 60）の
//　位置関係を考慮して、BUY_SIGNAL, SELL_SIGNAL. NO_SIGNALを返す・
// 
int judgeGMMA() {
   double gmma03_1 = 0.0;
   double gmma05_1 = 0.0;
   double gmma08_1 = 0.0;
   double gmma10_1 = 0.0;
   double gmma12_1 = 0.0;
   double gmma15_1 = 0.0;
   double gmma03_2 = 0.0;
   double gmma05_2 = 0.0;
   double gmma08_2 = 0.0;
   double gmma10_2 = 0.0;
   double gmma12_2 = 0.0;
   double gmma15_2 = 0.0;

   double gmma30_1 = 0.0;
   double gmma35_1 = 0.0;
   double gmma40_1 = 0.0;
   double gmma45_1 = 0.0;
   double gmma50_1 = 0.0;
   double gmma60_1 = 0.0;
   double gmma30_2 = 0.0;
   double gmma35_2 = 0.0;
   double gmma40_2 = 0.0;
   double gmma45_2 = 0.0;
   double gmma50_2 = 0.0;
   double gmma60_2 = 0.0;
   double gmma60_3 = 0.0;
   double gmma60_4 = 0.0;

   int gmmaFlag  = 0; //上から3～60の順に並んだら上昇局面gmmaFlag=1
   int gmmaFlag2 = 0; //同じ時間帯で、前々期より前期のiMAの方がより大きければ上昇局面gmmaFlag2=1
   int flgBuySELL = NO_SIGNAL; //前々期より前期のiMAの方がより大きければ上昇局面gmmaFlag3=1

   //上から3～60の順に並んだら上昇局面gmmaFlag=1
   //基本的には長期線が大事で、上向きなら上昇トレンド、下向きなら下降トレンド
   //
   //iMAの呼び出しを削減することで、処理を高速化している。
   // まずは、より短期のiMAがより長期のiMAの上にあること。
   
   // gmma03_1は、以降の、下降局面でも使用するため、事前に取得する。
   gmma03_1 =iMA(global_Symbol,0,3,0,MODE_EMA,PRICE_CLOSE,1); 
/*
printf( "[%d]エラー gmma03_1=%s  gmma05_1=%s  gmma08_1=%s  " , __LINE__, 
         DoubleToStr(iMA(global_Symbol,0,3,0,MODE_EMA,PRICE_CLOSE,1)),
         DoubleToStr(iMA(global_Symbol,0,5,0,MODE_EMA,PRICE_CLOSE,1)),
         DoubleToStr(iMA(global_Symbol,0,8,0,MODE_EMA,PRICE_CLOSE,1))
         );
printf( "[%d]エラー gmma10_1=%s  gmma12_1=%s  gmma15_1=%s  " , __LINE__, 
         DoubleToStr(iMA(global_Symbol,0,10,0,MODE_EMA,PRICE_CLOSE,1)),
         DoubleToStr(iMA(global_Symbol,0,12,0,MODE_EMA,PRICE_CLOSE,1)),
         DoubleToStr(iMA(global_Symbol,0,15,0,MODE_EMA,PRICE_CLOSE,1))
         );
         
printf( "[%d]エラー gmma30_1=%s  gmma35_1=%s  gmma40_1=%s  " , __LINE__, 
         DoubleToStr(iMA(global_Symbol,0,30,0,MODE_EMA,PRICE_CLOSE,1)),
         DoubleToStr(iMA(global_Symbol,0,35,0,MODE_EMA,PRICE_CLOSE,1)),
         DoubleToStr(iMA(global_Symbol,0,40,0,MODE_EMA,PRICE_CLOSE,1))
         );
printf( "[%d]エラー gmma45_1=%s  gmma50_1=%s  gmma60_1=%s  " , __LINE__, 
         DoubleToStr(iMA(global_Symbol,0,45,0,MODE_EMA,PRICE_CLOSE,1)),
         DoubleToStr(iMA(global_Symbol,0,50,0,MODE_EMA,PRICE_CLOSE,1)),
         DoubleToStr(iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,1))
         );         
*/         
   if(gmma03_1 > 0) {
      gmma05_1 =iMA(global_Symbol,0,5,0,MODE_EMA,PRICE_CLOSE,1);
      if(gmma05_1 > 0 && gmma03_1 > gmma05_1) {
         gmma08_1 =iMA(global_Symbol,0,8,0,MODE_EMA,PRICE_CLOSE,1);
         if(gmma08_1 > 0 && gmma05_1 > gmma08_1) {
            gmma10_1 =iMA(global_Symbol,0,10,0,MODE_EMA,PRICE_CLOSE,1);
            if(gmma10_1 > 0 &&  gmma08_1 > gmma10_1) {
               gmma12_1 =iMA(global_Symbol,0,12,0,MODE_EMA,PRICE_CLOSE,1);
               if(gmma12_1 > 0 && gmma10_1 > gmma12_1) {
                  gmma15_1 =iMA(global_Symbol,0,15,0,MODE_EMA,PRICE_CLOSE,1);
                  if(gmma15_1 > 0 && gmma12_1> gmma15_1) {
                     gmma30_1 = iMA(global_Symbol,0,30,0,MODE_EMA,PRICE_CLOSE,1);
                     // 以下、長期組の比較。比較的短期が、より大きい場合を探す；。
                     if(gmma30_1 > 0 && gmma15_1 > gmma30_1) {
                        gmma35_1 = iMA(global_Symbol,0,35,0,MODE_EMA,PRICE_CLOSE,1);
                        if(gmma35_1 > 0 && gmma30_1 > gmma35_1) {
                           gmma40_1 =iMA(global_Symbol,0,40,0,MODE_EMA,PRICE_CLOSE,1);
                           if(gmma40_1 > 0 && gmma35_1 > gmma40_1) {
                              gmma45_1 =iMA(global_Symbol,0,45,0,MODE_EMA,PRICE_CLOSE,1);
                              if(gmma45_1 > 0 && gmma40_1 > gmma45_1) {
                                 gmma50_1 =iMA(global_Symbol,0,50,0,MODE_EMA,PRICE_CLOSE,1);
                                 if(gmma50_1 > 0 && gmma45_1 > gmma50_1) {
                                    gmma60_1 =iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,1);
                                    if(gmma60_1 > 0 && gmma50_1 > gmma60_1) {
                                       // 以上、短期のiMAが長期のiMAより上にあることを確認する。
                                       // gmmaFlag = 1;を代入する。
                                       gmmaFlag = 1;
                                    }
                                 }
                              }
                           }
                        }
                     }
                  }
               }
            }
         }
      }
   }
   // より短期のiMAが上位、より長期のiMAが下位になっていることを前提(gmmaFlag == 1)として、
   // 各期で上昇中であること(gmmaFlag2 = 1)を次の比較により確認する。
   // まずは、短期組のシフト１の各iMAが、シフト２の各iMAより大きければ、上昇中（gmmaFlag2 = 1）とする。
   if(gmmaFlag == 1) {
      gmma03_2 = iMA(global_Symbol,0,3,0,MODE_EMA,PRICE_CLOSE,2);
      if(gmma03_2 > 0 && gmma03_1 > gmma03_2 ) {
         gmma05_2 =iMA(global_Symbol,0,5,0,MODE_EMA,PRICE_CLOSE,2);
         if(gmma05_2 > 0 && gmma05_1 > gmma05_2 ) {
            gmma08_2 =iMA(global_Symbol,0,8,0,MODE_EMA,PRICE_CLOSE,2);
            if(gmma08_2 > 0 && gmma08_1 > gmma08_2 ) {
               gmma10_2 =iMA(global_Symbol,0,10,0,MODE_EMA,PRICE_CLOSE,2);
               if(gmma10_2 > 0 && gmma10_1 > gmma10_2 ) {
                  gmma12_2 =iMA(global_Symbol,0,12,0,MODE_EMA,PRICE_CLOSE,2);
                  if(gmma12_2 > 0 && gmma12_1 > gmma12_2) {
                     gmma15_2=iMA(global_Symbol,0,15,0,MODE_EMA,PRICE_CLOSE,2);                  
                     if(gmma15_2 > 0 && gmma15_1 > gmma15_2) {
                        gmmaFlag2 = 1;
                     }
                  }
               }              
            }
         }
      }
      // 次は、長期組のシフト１の各iMAが、シフト２の各iMAより大きければ、上昇中（gmmaFlag3 = 1）とする。
      if(gmmaFlag2== 1) {
         gmma30_2 = iMA(global_Symbol,0,30,0,MODE_EMA,PRICE_CLOSE,2);
         if(gmma30_2 > 0 && gmma30_1 > gmma30_2) {
            gmma35_2 = iMA(global_Symbol,0,35,0,MODE_EMA,PRICE_CLOSE,2);
            if(gmma35_2 > 0 && gmma35_1 > gmma35_2) {
               gmma40_2 = iMA(global_Symbol,0,40,0,MODE_EMA,PRICE_CLOSE,2);
               if(gmma40_2 > 0 && gmma40_1 > gmma40_2) {
                  gmma45_2 = iMA(global_Symbol,0,45,0,MODE_EMA,PRICE_CLOSE,2);
                  if(gmma45_2 > 0 && gmma45_1 > gmma45_2) {
                     gmma50_2 = iMA(global_Symbol,0,50,0,MODE_EMA,PRICE_CLOSE,2);
                     if(gmma50_2 > 0 && gmma50_1 > gmma50_2) {
                        gmma60_2 = iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,2);
                        gmma60_3 = iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,3);                        
                        gmma60_4 = iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,4);
                        if(gmma60_2 > 0 && gmma60_3 > 0 &&gmma60_4 > 0 &&
                           gmma60_1 > gmma60_2 && gmma60_2 > gmma60_3 &&gmma60_3 > gmma60_4) {
                              flgBuySELL = BUY_SIGNAL;
                        }
                     }
                  }
               }
            }
         }
      }
      else {
      //gmmaFlag2== 1以外のため、何もしない。
      }
   }
   else {
      //gmmaFlag1== 1以外のため、何もしない。
   }

   //上から60～3の順に並んだら下降局面gmmaFlag=-1
   if(gmma03_1 > 0) {
      gmma05_1 =iMA(global_Symbol,0,5,0,MODE_EMA,PRICE_CLOSE,1);
      if(gmma05_1 > 0 && gmma03_1 < gmma05_1) {
         gmma08_1 =iMA(global_Symbol,0,8,0,MODE_EMA,PRICE_CLOSE,1);
         if(gmma08_1 > 0 && gmma05_1 < gmma08_1) {
            gmma10_1 =iMA(global_Symbol,0,10,0,MODE_EMA,PRICE_CLOSE,1);
            if(gmma10_1 > 0 &&  gmma08_1 < gmma10_1) {
               gmma12_1 =iMA(global_Symbol,0,12,0,MODE_EMA,PRICE_CLOSE,1);
               if(gmma12_1 > 0 && gmma10_1 < gmma12_1) {
                  gmma15_1 =iMA(global_Symbol,0,15,0,MODE_EMA,PRICE_CLOSE,1);
                  if(gmma15_1 > 0 && gmma12_1 < gmma15_1) {
                     gmma30_1 = iMA(global_Symbol,0,30,0,MODE_EMA,PRICE_CLOSE,1);
                     // 以下、長期組の比較。比較的短期が、より大きい場合を探す；。
                     if(gmma30_1 > 0 && gmma15_1 < gmma30_1) {
                        gmma35_1 = iMA(global_Symbol,0,35,0,MODE_EMA,PRICE_CLOSE,1);
                        if(gmma35_1 > 0 && gmma30_1 < gmma35_1) {
                           gmma40_1 =iMA(global_Symbol,0,40,0,MODE_EMA,PRICE_CLOSE,1);
                           if(gmma40_1 > 0 && gmma35_1 < gmma40_1) {
                              gmma45_1 =iMA(global_Symbol,0,45,0,MODE_EMA,PRICE_CLOSE,1);
                              if(gmma45_1 > 0 && gmma40_1 < gmma45_1) {
                                 gmma50_1 =iMA(global_Symbol,0,50,0,MODE_EMA,PRICE_CLOSE,1);
                                 if(gmma50_1 > 0 && gmma45_1 < gmma50_1) {
                                    gmma60_1 =iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,1);
                                    if(gmma60_1 > 0 && gmma50_1 < gmma60_1) {
                                       gmmaFlag = -11;
                                    }
                                 }
                              }
                           }
                        }
                     }
                  }
               }
            }
         }
      }
   }
   // より短期のiMAが上位、より長期のiMAが下位になっていることを前提(gmmaFlag == 1)として、
   // 各期で上昇中であること(gmmaFlag2 = 1)を次の比較により確認する。
   // まずは、短期組のシフト１の各iMAが、シフト２の各iMAより大きければ、上昇中（gmmaFlag2 = 1）とする。
   if(gmmaFlag == -11) {
      gmma03_2 = iMA(global_Symbol,0,3,0,MODE_EMA,PRICE_CLOSE,2);
      if(gmma03_2 > 0 && gmma03_1 < gmma03_2 ) {
         gmma05_2 =iMA(global_Symbol,0,5,0,MODE_EMA,PRICE_CLOSE,2);
         if(gmma05_2 > 0 && gmma05_1 < gmma05_2 ) {
            gmma08_2 =iMA(global_Symbol,0,8,0,MODE_EMA,PRICE_CLOSE,2);
            if(gmma08_2 > 0 && gmma08_1 < gmma08_2 ) {
               gmma10_2 =iMA(global_Symbol,0,10,0,MODE_EMA,PRICE_CLOSE,2);
               if(gmma10_2 > 0 && gmma10_1 < gmma10_2 ) {
                  gmma12_2 =iMA(global_Symbol,0,12,0,MODE_EMA,PRICE_CLOSE,2);
                  if(gmma12_2 > 0 && gmma12_1 < gmma12_2) {
                     gmma15_2=iMA(global_Symbol,0,15,0,MODE_EMA,PRICE_CLOSE,2);                  
                     if(gmma15_2 > 0 && gmma15_1 < gmma15_2) {
                        gmmaFlag2 = -11;
                     }
                  }
               }              
            }
         }
      }
      // 次は、長期組のシフト１の各iMAが、シフト２の各iMAより大きければ、上昇中（gmmaFlag3 = 1）とする。
      if(gmmaFlag2== -11) {
         gmma30_2 = iMA(global_Symbol,0,30,0,MODE_EMA,PRICE_CLOSE,2);
         if(gmma30_2 > 0 && gmma30_2 < gmma30_1) {
            gmma35_2 = iMA(global_Symbol,0,35,0,MODE_EMA,PRICE_CLOSE,2);
            if(gmma35_2 > 0 && gmma35_2 < gmma35_1) {
               gmma40_2 = iMA(global_Symbol,0,40,0,MODE_EMA,PRICE_CLOSE,2);
               if(gmma40_2 > 0 && gmma40_2 < gmma40_1) {
                  gmma45_2 = iMA(global_Symbol,0,45,0,MODE_EMA,PRICE_CLOSE,2);
                  if(gmma45_2 > 0 && gmma45_2 < gmma45_1) {
                     gmma50_2 = iMA(global_Symbol,0,50,0,MODE_EMA,PRICE_CLOSE,2);
                     if(gmma50_2 > 0 && gmma50_2 < gmma50_1) {
                        gmma60_2 = iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,2);
                        gmma60_3 = iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,3);                        
                        gmma60_4 = iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,4);
                        if(gmma60_2 > 0 && gmma60_3 > 0 &&gmma60_4 > 0 &&
                           gmma60_1 < gmma60_2 && gmma60_2 < gmma60_3 &&gmma60_3 < gmma60_4) {
                              flgBuySELL = SELL_SIGNAL;
                        }
                     }
                  }
               }
            }
         }
      }
      else {
      //gmmaFlag2== 1以外のため、何もしない。
      }
   }
   else {
      //gmmaFlag1== 1以外のため、何もしない。
   }
/*
/** 20210921　短期（3～25)と長期（30～60）がゴールデンクロス・デッドクロスをしていることを
    条件としていたが、条件が厳しすぎるため、除外した。
    あらためて導入する際は、ロジックの修正が必要。
   bool mCrossFlag1 = false;
   bool mCrossFlag2 = false;
   int i;
   
   i = 2;

   //短期の最大値を求める
   double mingmma03_25 = iMA(global_Symbol,0,3,0,MODE_EMA,PRICE_CLOSE,3);
   if( iMA(global_Symbol,0,5,0,MODE_EMA,PRICE_CLOSE,3) < mingmma03_25) {
		mingmma03_25 = iMA(global_Symbol,0,5,0,MODE_EMA,PRICE_CLOSE,i);
   }
   if( iMA(global_Symbol,0,8,0,MODE_EMA,PRICE_CLOSE,3) < mingmma03_25) {
		mingmma03_25 = iMA(global_Symbol,0,8,0,MODE_EMA,PRICE_CLOSE,i);
   }
   if( iMA(global_Symbol,0,10,0,MODE_EMA,PRICE_CLOSE,3) < mingmma03_25) {
		mingmma03_25 = iMA(global_Symbol,0,10,0,MODE_EMA,PRICE_CLOSE,i);
   }
   if( iMA(global_Symbol,0,12,0,MODE_EMA,PRICE_CLOSE,3) < mingmma03_25) {
		mingmma03_25 = iMA(global_Symbol,0,12,0,MODE_EMA,PRICE_CLOSE,i);
   }
   if( iMA(global_Symbol,0,15,0,MODE_EMA,PRICE_CLOSE,3) < mingmma03_25) {
		mingmma03_25 = iMA(global_Symbol,0,15,0,MODE_EMA,PRICE_CLOSE,i);
   }
  
	//長期の最大値を求める
   double maxgmma30_60 = iMA(global_Symbol,0,30,0,MODE_EMA,PRICE_CLOSE,3);
   if( iMA(global_Symbol,0,35,0,MODE_EMA,PRICE_CLOSE,3) > maxgmma30_60) {
		maxgmma30_60 = iMA(global_Symbol,0,35,0,MODE_EMA,PRICE_CLOSE,i);
   }
   if( iMA(global_Symbol,0,40,0,MODE_EMA,PRICE_CLOSE,3) > maxgmma30_60) {
		maxgmma30_60 = iMA(global_Symbol,0,40,0,MODE_EMA,PRICE_CLOSE,i);
   }
   if( iMA(global_Symbol,0,45,0,MODE_EMA,PRICE_CLOSE,3) > maxgmma30_60) {
		maxgmma30_60 = iMA(global_Symbol,0,45,0,MODE_EMA,PRICE_CLOSE,i);
   }
   if( iMA(global_Symbol,0,50,0,MODE_EMA,PRICE_CLOSE,3) > maxgmma30_60) {
		maxgmma30_60 = iMA(global_Symbol,0,50,0,MODE_EMA,PRICE_CLOSE,i);
   }
   if( iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,3) > maxgmma30_60) {
		maxgmma30_60 = iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,i);
   }

	//短期の最小値が長期の最大値未満の時、いずれかの線がデッドクロス状態にあることを意味する。
	if( mingmma03_25 < maxgmma30_60) {
		//全ての短期＞すべての長期という条件と合わせることで、
		//ゴールデンクロスを示す。
		mCrossFlag1 = true;  
	}
  

   mCrossFlag2 = false;
   double maxgmma03_25 = iMA(global_Symbol,0, 3,0,MODE_EMA,PRICE_CLOSE,3);
  	//短期の最大値を求める
	if( iMA(global_Symbol,0,5,0,MODE_EMA,PRICE_CLOSE,3) > maxgmma03_25) {
	   maxgmma03_25 = iMA(global_Symbol,0,5,0,MODE_EMA,PRICE_CLOSE,i);
   }
	if( iMA(global_Symbol,0,8,0,MODE_EMA,PRICE_CLOSE,3) > maxgmma03_25) {
	   maxgmma03_25 = iMA(global_Symbol,0,8,0,MODE_EMA,PRICE_CLOSE,i);
   }
	if( iMA(global_Symbol,0,10,0,MODE_EMA,PRICE_CLOSE,3) > maxgmma03_25) {
	   maxgmma03_25 = iMA(global_Symbol,0,10,0,MODE_EMA,PRICE_CLOSE,i);
   }
	if( iMA(global_Symbol,0,12,0,MODE_EMA,PRICE_CLOSE,3) > maxgmma03_25) {
	   maxgmma03_25 = iMA(global_Symbol,0,12,0,MODE_EMA,PRICE_CLOSE,i);
   }
	if( iMA(global_Symbol,0,15,0,MODE_EMA,PRICE_CLOSE,3) > maxgmma03_25) {
	   maxgmma03_25 = iMA(global_Symbol,0,15,0,MODE_EMA,PRICE_CLOSE,i);
   }

   double mingmma30_60 = iMA(global_Symbol,0,30,0,MODE_EMA,PRICE_CLOSE,3);
	//長期の最小値を求める
	if( iMA(global_Symbol,0,35,0,MODE_EMA,PRICE_CLOSE,3) < mingmma30_60) {
	   mingmma30_60 = iMA(global_Symbol,0,35,0,MODE_EMA,PRICE_CLOSE,i);
   }     
	if( iMA(global_Symbol,0,40,0,MODE_EMA,PRICE_CLOSE,3) < mingmma30_60) {
	   mingmma30_60 = iMA(global_Symbol,0,40,0,MODE_EMA,PRICE_CLOSE,i);
   }
	if( iMA(global_Symbol,0,45,0,MODE_EMA,PRICE_CLOSE,3) < mingmma30_60) {
	   mingmma30_60 = iMA(global_Symbol,0,45,0,MODE_EMA,PRICE_CLOSE,i);
   }
	if( iMA(global_Symbol,0,50,0,MODE_EMA,PRICE_CLOSE,3) < mingmma30_60) {
	   mingmma30_60 = iMA(global_Symbol,0,50,0,MODE_EMA,PRICE_CLOSE,i);
   }
	if( iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,3) < mingmma30_60) {
	   mingmma30_60 = iMA(global_Symbol,0,60,0,MODE_EMA,PRICE_CLOSE,i);
   }
	//短期の最大値が長期の最小値より大きいの時、いずれかの線がゴールデンクロス状態にあることを意味する
	if( maxgmma03_25 > mingmma30_60) {
		//全ての短期＜すべての長期という条件と合わせることで、
		//デッドクロスを示す。
		mCrossFlag2 = true;
	}
**/



   return flgBuySELL;
}
