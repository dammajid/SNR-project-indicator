//+------------------------------------------------------------------+
//|                                   Ultimate Trend Analyzer Pro.mq5 |
//|                                  Copyright 2025, Smart Trading Co |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Smart Trading Co"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property indicator_chart_window
#property indicator_buffers 15
#property indicator_plots   7

//--- Plot Trend Line
#property indicator_label1  "Main Trend"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

//--- Plot Upper Band
#property indicator_label2  "Upper Band"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrMediumSeaGreen
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

//--- Plot Lower Band
#property indicator_label3  "Lower Band"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrTomato
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

//--- Plot Buy Signal
#property indicator_label4  "Strong Buy"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  4

//--- Plot Sell Signal
#property indicator_label5  "Strong Sell"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrRed
#property indicator_width5  4

//--- Plot Weak Buy
#property indicator_label6  "Weak Buy"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrYellowGreen
#property indicator_width6  2

//--- Plot Weak Sell
#property indicator_label7  "Weak Sell"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrOrange
#property indicator_width7  2

//--- Enumerations
enum ENUM_SIGNAL_STRENGTH
{
   SIGNAL_WEAK,      // Weak Signal
   SIGNAL_MEDIUM,    // Medium Signal
   SIGNAL_STRONG     // Strong Signal
};

enum ENUM_TREND_MODE
{
   TREND_ADAPTIVE,   // Adaptive (Auto-adjust)
   TREND_AGGRESSIVE, // Aggressive (More signals)
   TREND_CONSERVATIVE // Conservative (Quality signals)
};

//--- Input Parameters - Main Settings
input group "========== Main Settings =========="
input ENUM_TREND_MODE    InpTrendMode = TREND_ADAPTIVE;        // Trading Mode
input int                InpTrendPeriod = 21;                   // Main Trend Period
input ENUM_MA_METHOD     InpTrendMethod = MODE_EMA;            // Trend MA Method
input ENUM_APPLIED_PRICE InpTrendPrice = PRICE_CLOSE;          // Applied Price

//--- Multi-Timeframe Analysis
input group "========== Multi-Timeframe Analysis =========="
input bool               InpUseMTF = true;                      // Use Multi-Timeframe
input ENUM_TIMEFRAMES    InpHigherTF = PERIOD_H1;              // Higher Timeframe

//--- Signal Settings
input group "========== Signal Configuration =========="
input int                InpFastMA = 8;                         // Fast MA Period
input int                InpSlowMA = 21;                        // Slow MA Period
input int                InpSignalMA = 5;                       // Signal Smoothing
input ENUM_SIGNAL_STRENGTH InpMinSignalStrength = SIGNAL_MEDIUM; // Minimum Signal Strength

//--- Oscillator Settings
input group "========== Oscillator Settings =========="
input int                InpRSIPeriod = 14;                     // RSI Period
input double             InpRSIOverbought = 65;                 // RSI Overbought
input double             InpRSIOversold = 35;                   // RSI Oversold
input int                InpStochPeriodK = 14;                  // Stochastic K Period
input int                InpStochPeriodD = 3;                   // Stochastic D Period
input int                InpStochSlowing = 3;                   // Stochastic Slowing

//--- Volatility & Risk
input group "========== Volatility & Dynamic Levels =========="
input int                InpATRPeriod = 14;                     // ATR Period
input double             InpATRMultiplier = 2.5;                // ATR Multiplier
input int                InpBBPeriod = 20;                      // Bollinger Period
input double             InpBBDeviation = 2.0;                  // BB Deviation
input bool               InpUseDynamicLevels = true;            // Dynamic SR Levels

//--- Filter Settings
input group "========== Advanced Filters =========="
input bool               InpUseVolumeFilter = true;             // Volume Filter
input double             InpMinVolumeMultiplier = 1.2;          // Min Volume Multiplier
input bool               InpUseTrendFilter = true;              // Trend Filter
input int                InpTrendFilterPeriod = 50;             // Trend Filter Period
input bool               InpUseTimeFilter = false;              // Time Filter
input int                InpStartHour = 8;                      // Trading Start Hour
input int                InpEndHour = 20;                       // Trading End Hour

//--- Alert Settings
input group "========== Alert & Notification =========="
input bool               InpShowAlerts = true;                  // Show Popup Alerts
input bool               InpShowPushNotif = true;               // Push Notifications
input bool               InpShowEmail = false;                  // Email Alerts
input bool               InpPlaySound = true;                   // Play Sound
input string             InpSoundFile = "alert2.wav";           // Sound File
input bool               InpShowOnChart = true;                 // Show Info Panel

//--- Visual Settings
input group "========== Visual Settings =========="
input color              InpBullColor = clrLime;                // Bullish Color
input color              InpBearColor = clrRed;                 // Bearish Color
input color              InpNeutralColor = clrGray;             // Neutral Color
input int                InpPanelX = 20;                        // Panel X Position
input int                InpPanelY = 50;                        // Panel Y Position

//--- Indicator Buffers
double MainTrendBuffer[];
double UpperBandBuffer[];
double LowerBandBuffer[];
double StrongBuyBuffer[];
double StrongSellBuffer[];
double WeakBuyBuffer[];
double WeakSellBuffer[];

//--- Calculation Buffers
double FastMABuffer[];
double SlowMABuffer[];
double SignalBuffer[];
double RSIBuffer[];
double ATRBuffer[];
double StochMainBuffer[];
double StochSignalBuffer[];
double BBMiddleBuffer[];

//--- Handles
int handleFastMA, handleSlowMA, handleRSI, handleATR;
int handleStoch, handleBB, handleMTF, handleTrendFilter;
int handleVolumeMA;

//--- Global Variables
datetime lastAlertTime;
datetime lastBarTime;
string lastSignalType;
double lastSignalPrice;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Indicator buffers mapping
   SetIndexBuffer(0, MainTrendBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, UpperBandBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, LowerBandBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, StrongBuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, StrongSellBuffer, INDICATOR_DATA);
   SetIndexBuffer(5, WeakBuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(6, WeakSellBuffer, INDICATOR_DATA);
   
   SetIndexBuffer(7, FastMABuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, SlowMABuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, SignalBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, RSIBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, ATRBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, StochMainBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(13, StochSignalBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(14, BBMiddleBuffer, INDICATOR_CALCULATIONS);
   
   //--- Set arrow codes
   PlotIndexSetInteger(3, PLOT_ARROW, 233);  // Strong Buy
   PlotIndexSetInteger(4, PLOT_ARROW, 234);  // Strong Sell
   PlotIndexSetInteger(5, PLOT_ARROW, 108);  // Weak Buy (small circle)
   PlotIndexSetInteger(6, PLOT_ARROW, 108);  // Weak Sell (small circle)
   
   //--- Create indicator handles
   handleFastMA = iMA(_Symbol, _Period, InpFastMA, 0, MODE_EMA, PRICE_CLOSE);
   handleSlowMA = iMA(_Symbol, _Period, InpSlowMA, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   handleATR = iATR(_Symbol, _Period, InpATRPeriod);
   handleStoch = iStochastic(_Symbol, _Period, InpStochPeriodK, InpStochPeriodD, InpStochSlowing, MODE_SMA, STO_LOWHIGH);
   handleBB = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   handleVolumeMA = iMA(_Symbol, _Period, 20, 0, MODE_SMA, VOLUME_TICK);
   handleTrendFilter = iMA(_Symbol, _Period, InpTrendFilterPeriod, 0, MODE_EMA, PRICE_CLOSE);
   
   if(InpUseMTF)
      handleMTF = iMA(_Symbol, InpHigherTF, InpTrendPeriod, 0, InpTrendMethod, InpTrendPrice);
   
   //--- Check handles
   if(handleFastMA == INVALID_HANDLE || handleSlowMA == INVALID_HANDLE || 
      handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE ||
      handleStoch == INVALID_HANDLE || handleBB == INVALID_HANDLE)
   {
      Print("Error creating indicator handles");
      return(INIT_FAILED);
   }
   
   //--- Set indicator properties
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   string short_name = "Ultimate Trend Analyzer Pro [" + EnumToString(InpTrendMode) + "]";
   IndicatorSetString(INDICATOR_SHORTNAME, short_name);
   
   //--- Initialize arrays as series
   ArraySetAsSeries(MainTrendBuffer, true);
   ArraySetAsSeries(UpperBandBuffer, true);
   ArraySetAsSeries(LowerBandBuffer, true);
   ArraySetAsSeries(StrongBuyBuffer, true);
   ArraySetAsSeries(StrongSellBuffer, true);
   ArraySetAsSeries(WeakBuyBuffer, true);
   ArraySetAsSeries(WeakSellBuffer, true);
   ArraySetAsSeries(FastMABuffer, true);
   ArraySetAsSeries(SlowMABuffer, true);
   ArraySetAsSeries(SignalBuffer, true);
   ArraySetAsSeries(RSIBuffer, true);
   ArraySetAsSeries(ATRBuffer, true);
   ArraySetAsSeries(StochMainBuffer, true);
   ArraySetAsSeries(StochSignalBuffer, true);
   ArraySetAsSeries(BBMiddleBuffer, true);
   
   lastAlertTime = 0;
   lastBarTime = 0;
   
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
   
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);
   
   int start = prev_calculated - 1;
   if(start < 0) start = 0;
   
   //--- Copy indicator data
   if(CopyBuffer(handleFastMA, 0, 0, rates_total, FastMABuffer) <= 0) return(0);
   if(CopyBuffer(handleSlowMA, 0, 0, rates_total, SlowMABuffer) <= 0) return(0);
   if(CopyBuffer(handleRSI, 0, 0, rates_total, RSIBuffer) <= 0) return(0);
   if(CopyBuffer(handleATR, 0, 0, rates_total, ATRBuffer) <= 0) return(0);
   if(CopyBuffer(handleStoch, 0, 0, rates_total, StochMainBuffer) <= 0) return(0);
   if(CopyBuffer(handleStoch, 1, 0, rates_total, StochSignalBuffer) <= 0) return(0);
   if(CopyBuffer(handleBB, 0, 0, rates_total, BBMiddleBuffer) <= 0) return(0);
   
   double volumeMA[];
   ArraySetAsSeries(volumeMA, true);
   if(InpUseVolumeFilter)
      CopyBuffer(handleVolumeMA, 0, 0, rates_total, volumeMA);
   
   double trendFilterMA[];
   ArraySetAsSeries(trendFilterMA, true);
   if(InpUseTrendFilter)
      CopyBuffer(handleTrendFilter, 0, 0, rates_total, trendFilterMA);
   
   //--- Main calculation loop
   for(int i = start; i < rates_total - 2; i++)
   {
      //--- Initialize signal buffers
      StrongBuyBuffer[i] = EMPTY_VALUE;
      StrongSellBuffer[i] = EMPTY_VALUE;
      WeakBuyBuffer[i] = EMPTY_VALUE;
      WeakSellBuffer[i] = EMPTY_VALUE;
      
      //--- Calculate Main Trend (Multi-layer adaptive)
      double macdValue = FastMABuffer[i] - SlowMABuffer[i];
      double macdPrev = FastMABuffer[i+1] - SlowMABuffer[i+1];
      
      MainTrendBuffer[i] = (FastMABuffer[i] * 0.5 + SlowMABuffer[i] * 0.3 + BBMiddleBuffer[i] * 0.2);
      
      //--- Calculate Dynamic Bands
      double atr = ATRBuffer[i] * InpATRMultiplier;
      UpperBandBuffer[i] = MainTrendBuffer[i] + atr;
      LowerBandBuffer[i] = MainTrendBuffer[i] - atr;
      
      //--- Time Filter
      bool timeFilterPass = true;
      if(InpUseTimeFilter)
      {
         MqlDateTime dt;
         TimeToStruct(time[i], dt);
         timeFilterPass = (dt.hour >= InpStartHour && dt.hour <= InpEndHour);
      }
      
      //--- Volume Filter
      bool volumeFilterPass = true;
      if(InpUseVolumeFilter && ArraySize(volumeMA) > i)
         volumeFilterPass = (tick_volume[i] >= volumeMA[i] * InpMinVolumeMultiplier);
      
      //--- Trend Filter
      bool bullishTrend = true;
      bool bearishTrend = true;
      if(InpUseTrendFilter && ArraySize(trendFilterMA) > i)
      {
         bullishTrend = (close[i] > trendFilterMA[i]);
         bearishTrend = (close[i] < trendFilterMA[i]);
      }
      
      if(i > 2)
      {
         //--- Detect Crossovers
         bool macdBullCross = (macdValue > 0 && macdPrev <= 0);
         bool macdBearCross = (macdValue < 0 && macdPrev >= 0);
         
         //--- RSI Conditions
         bool rsiOversold = (RSIBuffer[i] < InpRSIOversold && RSIBuffer[i] > RSIBuffer[i+1]);
         bool rsiOverbought = (RSIBuffer[i] > InpRSIOverbought && RSIBuffer[i] < RSIBuffer[i+1]);
         bool rsiNeutralBull = (RSIBuffer[i] > 50 && RSIBuffer[i] < InpRSIOverbought);
         bool rsiNeutralBear = (RSIBuffer[i] < 50 && RSIBuffer[i] > InpRSIOversold);
         
         //--- Stochastic Conditions
         bool stochOversold = (StochMainBuffer[i] < 20);
         bool stochOverbought = (StochMainBuffer[i] > 80);
         bool stochBullCross = (StochMainBuffer[i] > StochSignalBuffer[i] && StochMainBuffer[i+1] <= StochSignalBuffer[i+1]);
         bool stochBearCross = (StochMainBuffer[i] < StochSignalBuffer[i] && StochMainBuffer[i+1] >= StochSignalBuffer[i+1]);
         
         //--- Price Action
         bool priceAboveTrend = (close[i] > MainTrendBuffer[i]);
         bool priceBelowTrend = (close[i] < MainTrendBuffer[i]);
         bool bullishCandle = (close[i] > open[i]);
         bool bearishCandle = (close[i] < open[i]);
         
         //--- Calculate Signal Strength
         int buyScore = 0;
         int sellScore = 0;
         
         if(macdBullCross) buyScore += 3;
         if(rsiOversold) buyScore += 3;
         if(stochOversold && stochBullCross) buyScore += 2;
         if(priceAboveTrend) buyScore += 1;
         if(bullishCandle) buyScore += 1;
         if(bullishTrend) buyScore += 2;
         if(volumeFilterPass) buyScore += 1;
         
         if(macdBearCross) sellScore += 3;
         if(rsiOverbought) sellScore += 3;
         if(stochOverbought && stochBearCross) sellScore += 2;
         if(priceBelowTrend) sellScore += 1;
         if(bearishCandle) sellScore += 1;
         if(bearishTrend) sellScore += 2;
         if(volumeFilterPass) sellScore += 1;
         
         //--- Adjust scores based on mode
         double scoreMultiplier = 1.0;
         if(InpTrendMode == TREND_AGGRESSIVE) scoreMultiplier = 0.7;
         if(InpTrendMode == TREND_CONSERVATIVE) scoreMultiplier = 1.3;
         
         //--- Generate Signals based on strength
         if(buyScore >= 8 * scoreMultiplier && timeFilterPass)
         {
            if(InpMinSignalStrength <= SIGNAL_STRONG)
            {
               StrongBuyBuffer[i] = low[i] - atr * 0.3;
               if(i == 0 && time[0] != lastAlertTime)
                  SendSignalAlert("STRONG BUY", close[i], buyScore);
            }
         }
         else if(buyScore >= 5 * scoreMultiplier && timeFilterPass)
         {
            if(InpMinSignalStrength <= SIGNAL_MEDIUM)
            {
               StrongBuyBuffer[i] = low[i] - atr * 0.3;
               if(i == 0 && time[0] != lastAlertTime)
                  SendSignalAlert("BUY", close[i], buyScore);
            }
         }
         else if(buyScore >= 3 * scoreMultiplier && timeFilterPass)
         {
            if(InpMinSignalStrength <= SIGNAL_WEAK)
            {
               WeakBuyBuffer[i] = low[i] - atr * 0.2;
            }
         }
         
         if(sellScore >= 8 * scoreMultiplier && timeFilterPass)
         {
            if(InpMinSignalStrength <= SIGNAL_STRONG)
            {
               StrongSellBuffer[i] = high[i] + atr * 0.3;
               if(i == 0 && time[0] != lastAlertTime)
                  SendSignalAlert("STRONG SELL", close[i], sellScore);
            }
         }
         else if(sellScore >= 5 * scoreMultiplier && timeFilterPass)
         {
            if(InpMinSignalStrength <= SIGNAL_MEDIUM)
            {
               StrongSellBuffer[i] = high[i] + atr * 0.3;
               if(i == 0 && time[0] != lastAlertTime)
                  SendSignalAlert("SELL", close[i], sellScore);
            }
         }
         else if(sellScore >= 3 * scoreMultiplier && timeFilterPass)
         {
            if(InpMinSignalStrength <= SIGNAL_WEAK)
            {
               WeakSellBuffer[i] = high[i] + atr * 0.2;
            }
         }
         
         //--- Update info panel
         if(i == 0 && InpShowOnChart)
            UpdateInfoPanel(buyScore, sellScore, close[i], macdValue);
      }
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Send Alert Notification                                          |
//+------------------------------------------------------------------+
void SendSignalAlert(string signal, double price, int strength)
{
   lastAlertTime = iTime(_Symbol, _Period, 0);
   
   string message = "🎯 " + signal + " Signal [Score: " + IntegerToString(strength) + "]\n" +
                    "Symbol: " + _Symbol + "\n" +
                    "Timeframe: " + EnumToString((ENUM_TIMEFRAMES)_Period) + "\n" +
                    "Price: " + DoubleToString(price, _Digits) + "\n" +
                    "Mode: " + EnumToString(InpTrendMode);
   
   if(InpShowAlerts)
      Alert(message);
   
   if(InpShowPushNotif)
      SendNotification(message);
   
   if(InpShowEmail)
      SendMail("Ultimate Trend Analyzer - " + signal + " on " + _Symbol, message);
   
   if(InpPlaySound)
      PlaySound(InpSoundFile);
}

//+------------------------------------------------------------------+
//| Update Info Panel on Chart                                       |
//+------------------------------------------------------------------+
void UpdateInfoPanel(int buyScore, int sellScore, double price, double macd)
{
   string panelText = "═══ Ultimate Trend Analyzer Pro ═══\n";
   panelText += "Symbol: " + _Symbol + " | TF: " + EnumToString((ENUM_TIMEFRAMES)_Period) + "\n";
   panelText += "Mode: " + EnumToString(InpTrendMode) + "\n";
   panelText += "──────────────────────\n";
   panelText += "Buy Score: " + IntegerToString(buyScore) + " | Sell Score: " + IntegerToString(sellScore) + "\n";
   panelText += "Current Price: " + DoubleToString(price, _Digits) + "\n";
   panelText += "MACD: " + DoubleToString(macd, _Digits + 1) + "\n";
   
   string trend = "NEUTRAL";
   color trendColor = InpNeutralColor;
   if(buyScore > sellScore + 2) { trend = "BULLISH ↑"; trendColor = InpBullColor; }
   else if(sellScore > buyScore + 2) { trend = "BEARISH ↓"; trendColor = InpBearColor; }
   
   panelText += "Trend: " + trend;
   
   Comment(panelText);
}

//+------------------------------------------------------------------+
//| Indicator deinitialization function                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleFastMA != INVALID_HANDLE) IndicatorRelease(handleFastMA);
   if(handleSlowMA != INVALID_HANDLE) IndicatorRelease(handleSlowMA);
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);
   if(handleStoch != INVALID_HANDLE) IndicatorRelease(handleStoch);
   if(handleBB != INVALID_HANDLE) IndicatorRelease(handleBB);
   if(handleVolumeMA != INVALID_HANDLE) IndicatorRelease(handleVolumeMA);
   if(handleTrendFilter != INVALID_HANDLE) IndicatorRelease(handleTrendFilter);
   if(handleMTF != INVALID_HANDLE) IndicatorRelease(handleMTF);
   
   Comment("");
}
//+------------------------------------------------------------------+
