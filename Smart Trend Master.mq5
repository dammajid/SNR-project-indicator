//+------------------------------------------------------------------+
//|                                        Smart Trend Master Pro.mq5 |
//|                                  Copyright 2025, Smart Trading Co |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Smart Trading Co"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   4

//--- Plot Trend Line
#property indicator_label1  "Trend Line"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Plot Buy Signal
#property indicator_label2  "Buy Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  3

//--- Plot Sell Signal
#property indicator_label3  "Sell Signal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  3

//--- Plot Support/Resistance Zone
#property indicator_label4  "SR Zone"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrGold
#property indicator_style4  STYLE_DOT
#property indicator_width4  1

//--- Input Parameters
input int                InpFastMA = 12;              // Fast MA Period
input int                InpSlowMA = 26;              // Slow MA Period
input int                InpSignalMA = 9;             // Signal MA Period
input ENUM_MA_METHOD     InpMAMethod = MODE_EMA;      // MA Method
input int                InpRSIPeriod = 14;           // RSI Period
input double             InpRSIOverbought = 70;       // RSI Overbought Level
input double             InpRSIOversold = 30;         // RSI Oversold Level
input int                InpATRPeriod = 14;           // ATR Period
input double             InpATRMultiplier = 2.0;      // ATR Multiplier
input bool               InpShowAlerts = true;        // Show Alerts
input bool               InpShowPushNotif = true;     // Push Notifications
input bool               InpShowEmail = false;        // Email Notifications
input color              InpBullishColor = clrLime;   // Bullish Color
input color              InpBearishColor = clrRed;    // Bearish Color

//--- Indicator Buffers
double TrendBuffer[];
double BuySignalBuffer[];
double SellSignalBuffer[];
double SRZoneBuffer[];
double FastMABuffer[];
double SlowMABuffer[];
double RSIBuffer[];
double ATRBuffer[];

//--- Global Variables
int handleFastMA, handleSlowMA, handleRSI, handleATR;
datetime lastAlertTime;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, TrendBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, BuySignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, SellSignalBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, SRZoneBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, FastMABuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, SlowMABuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, RSIBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, ATRBuffer, INDICATOR_CALCULATIONS);
   
   //--- Set arrow codes
   PlotIndexSetInteger(1, PLOT_ARROW, 233);  // Up arrow
   PlotIndexSetInteger(2, PLOT_ARROW, 234);  // Down arrow
   
   //--- Create handles for indicators
   handleFastMA = iMA(_Symbol, _Period, InpFastMA, 0, InpMAMethod, PRICE_CLOSE);
   handleSlowMA = iMA(_Symbol, _Period, InpSlowMA, 0, InpMAMethod, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   handleATR = iATR(_Symbol, _Period, InpATRPeriod);
   
   if(handleFastMA == INVALID_HANDLE || handleSlowMA == INVALID_HANDLE || 
      handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
   }
   
   //--- Set indicator digits
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   
   //--- Set indicator short name
   string short_name = "Smart Trend Master Pro (" + 
                       IntegerToString(InpFastMA) + "," + 
                       IntegerToString(InpSlowMA) + "," + 
                       IntegerToString(InpSignalMA) + ")";
   IndicatorSetString(INDICATOR_SHORTNAME, short_name);
   
   //--- Initialize arrays
   ArraySetAsSeries(TrendBuffer, true);
   ArraySetAsSeries(BuySignalBuffer, true);
   ArraySetAsSeries(SellSignalBuffer, true);
   ArraySetAsSeries(SRZoneBuffer, true);
   ArraySetAsSeries(FastMABuffer, true);
   ArraySetAsSeries(SlowMABuffer, true);
   ArraySetAsSeries(RSIBuffer, true);
   ArraySetAsSeries(ATRBuffer, true);
   
   //--- Initialize last alert time
   lastAlertTime = 0;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < InpSlowMA + InpSignalMA)
      return(0);
   
   //--- Set arrays as series
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   //--- Calculate start position
   int start = prev_calculated - 1;
   if(start < 0) start = 0;
   
   //--- Copy indicator data
   if(CopyBuffer(handleFastMA, 0, 0, rates_total, FastMABuffer) <= 0) return(0);
   if(CopyBuffer(handleSlowMA, 0, 0, rates_total, SlowMABuffer) <= 0) return(0);
   if(CopyBuffer(handleRSI, 0, 0, rates_total, RSIBuffer) <= 0) return(0);
   if(CopyBuffer(handleATR, 0, 0, rates_total, ATRBuffer) <= 0) return(0);
   
   //--- Main calculation loop
   for(int i = start; i < rates_total - 1; i++)
   {
      //--- Initialize buffers
      BuySignalBuffer[i] = EMPTY_VALUE;
      SellSignalBuffer[i] = EMPTY_VALUE;
      
      //--- Calculate trend line (weighted combination of MAs)
      TrendBuffer[i] = (FastMABuffer[i] * 0.6 + SlowMABuffer[i] * 0.4);
      
      //--- Calculate Support/Resistance zones using ATR
      double atrValue = ATRBuffer[i] * InpATRMultiplier;
      SRZoneBuffer[i] = TrendBuffer[i];
      
      //--- Detect signals
      if(i > 0)
      {
         bool bullishCrossover = (FastMABuffer[i] > SlowMABuffer[i]) && 
                                 (FastMABuffer[i+1] <= SlowMABuffer[i+1]);
         bool bearishCrossover = (FastMABuffer[i] < SlowMABuffer[i]) && 
                                 (FastMABuffer[i+1] >= SlowMABuffer[i+1]);
         
         bool rsiOversold = RSIBuffer[i] < InpRSIOversold;
         bool rsiOverbought = RSIBuffer[i] > InpRSIOverbought;
         
         double priceAboveTrend = close[i] > TrendBuffer[i];
         double priceBelowTrend = close[i] < TrendBuffer[i];
         
         //--- Buy Signal Conditions
         if(bullishCrossover && rsiOversold && priceAboveTrend)
         {
            BuySignalBuffer[i] = low[i] - atrValue * 0.5;
            
            //--- Send alerts for new bar only
            if(i == 0 && time[0] != lastAlertTime)
            {
               SendSignalAlert("BUY", close[i]);
               lastAlertTime = time[0];
            }
         }
         
         //--- Sell Signal Conditions
         if(bearishCrossover && rsiOverbought && priceBelowTrend)
         {
            SellSignalBuffer[i] = high[i] + atrValue * 0.5;
            
            //--- Send alerts for new bar only
            if(i == 0 && time[0] != lastAlertTime)
            {
               SendSignalAlert("SELL", close[i]);
               lastAlertTime = time[0];
            }
         }
      }
   }
   
   //--- Return value of prev_calculated for next call
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Send Alert Notification                                          |
//+------------------------------------------------------------------+
void SendSignalAlert(string signal, double price)
{
   if(!InpShowAlerts && !InpShowPushNotif && !InpShowEmail)
      return;
   
   string message = "Smart Trend Master Pro - " + signal + " Signal on " + 
                    _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)_Period) + 
                    " at price " + DoubleToString(price, _Digits);
   
   //--- Show popup alert
   if(InpShowAlerts)
      Alert(message);
   
   //--- Send push notification
   if(InpShowPushNotif)
      SendNotification(message);
   
   //--- Send email
   if(InpShowEmail)
      SendMail("Trading Signal - " + _Symbol, message);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   if(handleFastMA != INVALID_HANDLE)
      IndicatorRelease(handleFastMA);
   if(handleSlowMA != INVALID_HANDLE)
      IndicatorRelease(handleSlowMA);
   if(handleRSI != INVALID_HANDLE)
      IndicatorRelease(handleRSI);
   if(handleATR != INVALID_HANDLE)
      IndicatorRelease(handleATR);
   
   Comment("");
}
//+------------------------------------------------------------------+