//+------------------------------------------------------------------+
//VHFインディケータはこちら→http://mt4indifx.seesaa.net/article/424921034.html#more
#property copyright "Copyright c 2009, Brian Dee"
#property link      "briandee@selectfx.net"
 
//+------------------------------------------------------------------+
//extern double Lots = 0.1;
extern int RiskBoost=3; // 1-6 Your choice to strengthen lotsize when trading with the trend
 
extern int SVOSTakeProfit = 350;
extern int SVOSStopLoss = 90;
extern int SVOSTrailingStop = 150;
 
extern int MAShift = 0;
extern int iSlippage = 5;

 
int StochKPeriod=8;
int StochDPeriod=3;
int StochSlowingPeriod=3;
extern int StochMAMethod=0; //MODE_SMA 0 MODE_EMA 1 MODE_SMMA 2 MODE_LWMA 3
extern int StochPriceField=0; //0=Low/High 1=Close/Close
 
 
int MACDFast_EMA_Period=10; // Number of periods for fast moving average
int MACDSlow_EMA_Period=25; // Number of periods for fast moving average
int MACDSignal_Period=5;    // 
 
extern double StdDevMin=0.3;    // 0.01=Ambitious 0.2=Conservative
 
extern double VHFThreshold=0.4; // 0.2=Ambitious 0.4=Conservative
 
extern int MaxNumTrendOrders=4;
extern int MaxNumRangeOrders=2;
 
double StdDevPeriod=20;
double VHFPeriod=20;
double SVOSiDoji=8.5; // Divisor for calculating body/height ratio of a candle
 
double dPivot, SVOSBuyLots, SVOSSellLots;
int SVOScnt, SVOSticket, SVOStotal, accounttotal, LatestOpenTicket;
bool IsTrending;
 
int TradeAction=0; // 1=Buy 2=Sell
string strSymbol=Symbol(); // Hard coded for this symbol
string strComment="SVOS";
int iPeriod=PERIOD_D1;

int mSVOSFlag = 0; 
 
/*
 
 
*/
 
 
 

int entrySVOS()
  {
//----
 
 
 
 
// ==========================================================================
// Check each tick section START 
 
 /*
   if(Bars<10)
     {
      Print("Bars less than 10");
      return(0);  
     }
   */  
   if(SVOSTrailingStop==0) SVOSTrailingStop=20; // Must have a Trailing Stop
   if(SVOSTrailingStop>0) LatestOpenTicket=CheckActiveTradesForStopLoss(); // Get this while checking stop loss
 
 
  
 
// Check each tick section END
// ==========================================================================
 
 
 
// ==========================================================================
 
// Once per bar section START
if(Volume[0]>1) return (0);
 
//============================ INFO FROM OTHER PERIODS/INSTRUMENTS =======================================
   double EMA_D5_1 = iMA(strSymbol,PERIOD_D1,5,0,MODE_EMA,PRICE_CLOSE,1);
   double EMA_D5_0 = iMA(strSymbol,PERIOD_D1,5,0,MODE_EMA,PRICE_CLOSE,0);
   double EMA_D20_0 = iMA(strSymbol,PERIOD_D1,20,0,MODE_EMA,PRICE_CLOSE,0);
   double EMA_D130_0 = iMA(strSymbol,PERIOD_MN1,6,0,MODE_EMA,PRICE_CLOSE,0);
   
 //============================ INFO FROM OTHER PERIODS/INSTRUMENTS =======================================
 
 
 
   double VHF_1 = iCustom(strSymbol,iPeriod,"MTF_VHF",VHFPeriod, 0,1) / 100;
   
   double STOCHM_1 = iStochastic(strSymbol,iPeriod,StochKPeriod,StochDPeriod,StochSlowingPeriod,StochMAMethod,StochPriceField, MODE_MAIN, 1);
   
   double STOCHS_1 = iStochastic(strSymbol,iPeriod,StochKPeriod,StochDPeriod,StochSlowingPeriod,StochMAMethod,StochPriceField, MODE_SIGNAL, 1);
   
   double STD_BB_1 = iStdDev(strSymbol,iPeriod,StdDevPeriod,MAShift,MODE_EMA,PRICE_CLOSE,1);
   
   double CLOSE_3 = Close[3];
   double CLOSE_2 = Close[2];
   double CLOSE_1 = Close[1];
  
   double OSMA_3 = iOsMA(strSymbol,iPeriod,MACDFast_EMA_Period,MACDSlow_EMA_Period,MACDSignal_Period,PRICE_CLOSE,3);
   double OSMA_2 = iOsMA(strSymbol,iPeriod,MACDFast_EMA_Period,MACDSlow_EMA_Period,MACDSignal_Period,PRICE_CLOSE,2);
   double OSMA_1 = iOsMA(strSymbol,iPeriod,MACDFast_EMA_Period,MACDSlow_EMA_Period,MACDSignal_Period,PRICE_CLOSE,1);
 
 Print("VHF_1==",VHF_1,"==VHFThreshold==",VHFThreshold);
   if(VHF_1 >= VHFThreshold) IsTrending=True;
   else IsTrending=False;
//if(sleepWhenRange() == true) IsTrending=False;
//else IsTrending=True;
   
      double O1 = Open[1];
      double O2 = Open[2];
      double O23 = Open[3];
      double H1 = High[1];
      double H2 = High[2];
      double H23 = High[3];
      double L1 = Low[1];
      double L2 = Low[2];
      double L3 = Low[3];
      double C1 = Close[1];
      double C2 = Close[2];
      double C3 = Close[3];
 
 // ==============================================================================
 // Handle closure conditions for SELL    
   
   if(SVOSIsBullishEngulfing()==1) CloseAllSellOrders(); // Close any SELL
   
   if(SVOSIsMorningStar()==1) CloseAllSellOrders(); // Close any SELL
 
   if ((IsTrending) && (OSMA_1 > 0)) CloseAllSellOrders(); // Use OSMA if VHF decides
   
   if ((IsTrending==False) && (STOCHM_1 >= STOCHS_1)) CloseAllSellOrders(); // Use Stochastic if VHF decides
 
 
    // Handle closure conditions for BUY   
    
   if(SVOSIsBearishEngulfing()==1)  CloseAllBuyOrders(); // Close any BUY
   
   if(SVOSIsEveningStar()==1)  CloseAllBuyOrders(); // Close any BUY
   
   if ((IsTrending) && (OSMA_1 < 0)) CloseAllBuyOrders(); // Use OSMA if VHF decides
 
   if ((IsTrending==False) && (STOCHM_1 <= STOCHS_1)) CloseAllBuyOrders(); // Use Stochastic if VHF decides
     
  
  
 
// ==========================================================================
// Check once each bar section START
 
 
  SVOStotal=ActiveTradesForMagicNumber(strSymbol, MagicNumberSVOS);
 
 
  if ((IsTrending) && (SVOStotal >= MaxNumTrendOrders)) return(0); // Enough orders already!
  
  if ((IsTrending==False) && (SVOStotal >= MaxNumRangeOrders)) return(0); // Enough orders already!
  
// ==========================================================================
// Add INO index and Dollar Index in here for TP/SL and Lot sizing
// Lot Sizing START  
  
     SVOSBuyLots=Lots;
     SVOSSellLots=Lots;
     TradeAction=0;
 
  if ((EMA_D5_0 > EMA_D20_0) && (EMA_D5_0 > EMA_D5_1) && (EMA_D20_0 > EMA_D130_0))
    {
     SVOSBuyLots=RiskBoost*Lots;
     SVOSSellLots=Lots;
    }
 
    if ((EMA_D5_0 < EMA_D20_0) && (EMA_D5_0 < EMA_D5_1) && (EMA_D20_0 < EMA_D130_0))
    {
     SVOSBuyLots=Lots;
     SVOSSellLots=RiskBoost*Lots;
    }
 
 
    
 // Lot Sizing END
// ==========================================================================
 
    // Assess for BUY
    
    if((SVOSIsEveningStar()==0) && (SVOSIsDojiCandle()==0) && (SVOSIsBearishEngulfing()==0) && (Close[1]>Open[1]) ) // no reversal or indecision sign
    {
    if((OSMA_1>0) && (OSMA_1 > OSMA_2) && (IsTrending) && (STD_BB_1 > StdDevMin)) TradeAction=1; // Use OSMA if VHF decides
    
    if((STOCHM_1 > STOCHS_1) && (IsTrending==False) && (STD_BB_1 > StdDevMin)) TradeAction=1; // Use Stochastic if VHF decides
    }
    
    // Assess for SELL
    
    if((SVOSIsMorningStar()==0) && (SVOSIsDojiCandle()==0) && (SVOSIsBullishEngulfing()==0) && (Close[1]<Open[1]) ) // no reversal or indecision sign
    {
    if((OSMA_1<0) && (OSMA_1 < OSMA_2) && (IsTrending) && (STD_BB_1 > StdDevMin)) TradeAction=2; // Use OSMA if VHF decides
    
    if((STOCHM_1 < STOCHS_1) && (IsTrending==False) && (STD_BB_1 > StdDevMin)) TradeAction=2; // Use Stochastic if VHF decides
    }
 
      // check for long position (BUY) possibility      
      if(TradeAction==1)
        {
          //SVOSticket=OrderSend(strSymbol,OP_BUY,SVOSBuyLots,Ask,iSlippage,Ask-SVOSStopLoss*Point,Ask+SVOSTakeProfit*Point,strComment,MagicNumberSVOS,0,Green);
	 SVOSticket=OrderSend(strSymbol,OP_BUY,SVOSBuyLots,Ask,iSlippage,0.0,0.0,strComment,MagicNumberSVOS,0,Green);         
         if(SVOSticket>0)
           {
		mSVOSFlag = OrderModify(SVOSticket, OrderOpenPrice(), Ask-SVOSStopLoss*Point,Ask+SVOSTakeProfit*Point, 0, MediumSeaGreen);	
           }
         else Print("Error opening BUY order : ",GetLastError()); 
           
         return(0); 
         
        }
      // check for short position (SELL) possibility
       if(TradeAction==2)
        {
//         SVOSticket=OrderSend(strSymbol,OP_SELL,SVOSSellLots,Bid,iSlippage,Bid+SVOSStopLoss*Point,Bid-SVOSTakeProfit*Point,strComment,MagicNumberSVOS,0,Red);
         SVOSticket=OrderSend(strSymbol,OP_SELL,SVOSSellLots,Bid,iSlippage,0.0,0.0,strComment,MagicNumberSVOS,0,Red);
         
         if(SVOSticket>0)
           {
		mSVOSFlag = OrderModify(SVOSticket, OrderOpenPrice(), Bid+SVOSStopLoss*Point,Bid-SVOSTakeProfit*Point, 0, MediumSeaGreen);	
           }
         else Print("Error opening SELL order : ",GetLastError()); 
           
         return(0); 
        }
 
 
// Check once each bar section END
 
 
 
   
//----
   return(0);
  }
//+------------------------------------------------------------------+
 
  void CloseAllBuyOrders()
  {
  int i, iTotalOrders;
  
   iTotalOrders=OrdersTotal()-1; // Rosh line
  
   for (i=iTotalOrders; i>=0; i--) // Rosh line      
   
   
   { 
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      { 
         if (OrderMagicNumber()==MagicNumberSVOS)
         { 
            if (OrderType()==OP_BUY) mSVOSFlag = OrderClose(OrderTicket(),OrderLots(),Bid,5,Violet);
            if (OrderType()==OP_BUYSTOP) mSVOSFlag = OrderDelete(OrderTicket());
            if (OrderType()==OP_BUYLIMIT) mSVOSFlag = OrderDelete(OrderTicket());
            
         }
      }
   }
}
 
  void CloseAllSellOrders()
  {
  int i, iTotalOrders;
   
   iTotalOrders=OrdersTotal()-1; // Rosh line
  
   for (i=iTotalOrders; i>=0; i--) // Rosh line     
   
   { 
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      { 
         if (OrderMagicNumber()==MagicNumberSVOS)
         { 
            if (OrderType()==OP_SELL) mSVOSFlag = OrderClose(OrderTicket(),OrderLots(),Ask,5,Violet);
            if (OrderType()==OP_SELLSTOP) mSVOSFlag = OrderDelete(OrderTicket());
            if (OrderType()==OP_SELLLIMIT) mSVOSFlag = OrderDelete(OrderTicket());
         }
      }
   }
}
 
int ActiveTradesForMagicNumber(string SymbolToCheck, int MagicNumberToCheck)
{
int icnt, itotal, retval;
 
retval=0;
itotal=OrdersTotal();
 
   for(icnt=0;icnt<itotal;icnt++)
     {
      mSVOSFlag = OrderSelect(icnt, SELECT_BY_POS, MODE_TRADES);
       // check for opened position, symbol & MagicNumber
      if(OrderType()<=OP_SELL && OrderSymbol()==SymbolToCheck  && OrderMagicNumber()==MagicNumberToCheck)  
        {
        
        retval++;
        
        //Print("Orders opened : ",retval);
        
        }
     }
 
return(retval);
}
 
int CheckActiveTradesForStopLoss()
{
int icnt, itotal;
int max=0;
 
itotal=OrdersTotal();
 
   for(icnt=0;icnt<itotal;icnt++) 
     {                               // order loop boundary
      mSVOSFlag = OrderSelect(icnt, SELECT_BY_POS, MODE_TRADES);
       // check for opened position, symbol & MagicNumber
      if(OrderType()==OP_SELL && OrderSymbol()==strSymbol  && OrderMagicNumber()==MagicNumberSVOS)  
        { 
         if (OrderTicket()>max)  max=OrderTicket(); // Check for latest open ticket
         
         if (OrderStopLoss()==0)
             {
              mSVOSFlag = OrderModify(OrderTicket(),OrderOpenPrice(),Ask+Point*SVOSTrailingStop,OrderTakeProfit(),0,Red);
             }    
        
 
         if((OrderOpenPrice()-Ask)>(Point*SVOSTrailingStop))
              {
               if(OrderStopLoss()>(Ask+Point*SVOSTrailingStop))
                  {
                   mSVOSFlag = OrderModify(OrderTicket(),OrderOpenPrice(),Ask+Point*SVOSTrailingStop,OrderTakeProfit(),0,Red);
                  }
              }
         
 
        }
        
        
       if(OrderType()==OP_BUY && OrderSymbol()==strSymbol  && OrderMagicNumber()==MagicNumberSVOS)  
        { 
         if (OrderTicket()>max)  max=OrderTicket(); // Check for latest open ticket
            if (OrderStopLoss()==0)
             {
              mSVOSFlag = OrderModify(OrderTicket(),OrderOpenPrice(),Bid-Point*SVOSTrailingStop,OrderTakeProfit(),0,Green);
             }
             
             if(Bid-OrderOpenPrice()>Point*SVOSTrailingStop)
                 {
                  if(OrderStopLoss()<Bid-Point*SVOSTrailingStop)
                    {
                     mSVOSFlag = OrderModify(OrderTicket(),OrderOpenPrice(),Bid-Point*SVOSTrailingStop,OrderTakeProfit(),0,Green);
                    }
                 }
              
        }
 
     }  // order loop boundary
 
return(max);
     
}
 
 
 
int SVOSIsMorningStar()
{int retval=0;
 
if(
    (SVOSBody(3) > SVOSBody(2)) &&  // Star body smaller than the previous one
    
    (SVOSBody(1) > SVOSBody(2)) && // Body of star smaller than bodies of first and last candles
    
    (Close[3] < Open[3]) && // First is a down candle
    
    (Close[1] > Open[1]) && // Third is an up candle
    
    (Close[1] > (SVOSBodyLo(3) + SVOSBody(3)*0.5)) // The third candle closes above the midpoint of the first candle
    
  )
  retval=1;
 
 return (retval);
 
}
 
int SVOSIsEveningStar()
{int retval=0;
 
if(
    (SVOSBody(3) > SVOSBody(2)) &&  // Star body smaller than the previous one
    
    (SVOSBody(1) > SVOSBody(2)) && // Body of star smaller than bodies of first and last candles
    
    (Close[3] > Open[3]) && // First is an up candle
    
    (Close[1] < Open[1]) && // Third is a down candle
    
    (Close[1] < (SVOSBodyHi(3) - SVOSBody(3)*0.5)) // The third candle closes below the midpoint of the first candle
    
  )
  retval=1;
 
 return (retval);
 
}
 
int SVOSIsBullishEngulfing()
{int retval=0;
 
if(
 
    (Close[2] < Open[2]) && // First is a down candle
    
    (Close[1] > Open[1]) && // Second is an up candle
    
    (SVOSBody(2) < SVOSBody(1)) // First engulfed by second
 
  )
  retval=1;
 
 return (retval);
 
}
 
int SVOSIsBearishEngulfing()
{int retval=0;
 
if(
 
    (Close[2] > Open[2]) && // First is an up candle
    
    (Close[1] < Open[1]) && // Second is a down candle
    
    (SVOSBody(2) < SVOSBody(1)) // First engulfed by second
 
  )
  retval=1;
 
 return (retval);
 
}
 
int SVOSIsDojiCandle()
{int retval=0;
 
if(
   (SVOSBody(1) < ((High[1] - Low[1])/SVOSiDoji))
  )
  retval=1;
 
 return (retval);
 
}
 
 
double SVOSBody (int iCandle)
{ double CandleOpen, CandleClose;
 
CandleOpen=Open[iCandle];
CandleClose=Close[iCandle];
 
return (MathMax(CandleOpen, CandleClose)-(MathMin(CandleOpen, CandleClose)));
}
 
 
double SVOSBodyLo (int iCandle)
{ 
return (MathMin(Open[iCandle], Close[iCandle]));
}
 
 
double SVOSBodyHi (int iCandle)
{ 
return (MathMax(Open[iCandle], Close[iCandle]));
}
 
 
 
 
 
 
void Display_Info()
{
   Comment("SelectFX Expert Adviser\n",
            "Desc: ",strComment,"\n",
            "Magic Number: ", MagicNumberSVOS,"\n",
            "Forex Account Server:",AccountServer(),"\n",
            "Account Balance:  $",AccountBalance(),"\n",
            "Lots:  ",Lots,"\n",
            "Symbol: ", Symbol(),"\n",
            "Price:  ",NormalizeDouble(Bid,4),"\n",
            "Pip Spread:  ",MarketInfo(strSymbol,MODE_SPREAD),"\n",
            "Date: ",Month(),"-",Day(),"-",Year()," Server Time: ",Hour(),":",Minute(),":",Seconds(),"\n",
            "Minimum Lot Size: ",MarketInfo(Symbol(),MODE_MINLOT));
   return;
}
 
void Check_Settings()
{
    if(Period()!=iPeriod)
     {
      Alert("Period set to: ", Period(), " is not correct for this EA!");
      return;  
     }
     
    if(Symbol()!=strSymbol)
     {
      Alert("Symbol set to: ", Symbol(), " is not correct for this EA!");
      return;  
     }
     
     if(Lots < MarketInfo(Symbol(),MODE_MINLOT))
     {
      Alert("Lot size set too low, minimum is: ", MODE_MINLOT, " for this Account!");
      return;  
     }
     
   return;
}
