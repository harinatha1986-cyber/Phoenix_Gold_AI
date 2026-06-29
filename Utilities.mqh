//+------------------------------------------------------------------+
//|                                                    Utilities.mqh |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| A comprehensive utility class for price normalization, time     |
//| calculations, and MQL5 helper conversions.                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"
#property once

//+------------------------------------------------------------------+
//| Class CUtilities                                                 |
//| Static utility functions for MT5 trading operations             |
//+------------------------------------------------------------------+
class CUtilities
{
public:
   // Normalize price to symbol digits and tick size
   static double  NormalizePrice(const string symbol, const double price);
   
   // Convert pips to points based on symbol configuration
   static double  PipsToPoints(const string symbol, const double pips);
   
   // Convert points to price offset
   static double  PointsToPrice(const string symbol, const double points);
   
   // Get minutes elapsed since midnight for a given time
   static int     TimeToMinutes(const datetime time);
   
   // Check if a given time falls on a weekend
   static bool    IsWeekend(const datetime time);
   
   // Parse "HH:MM" string format into minutes since midnight
   static int     StringToMinutes(const string time_str);
   
   // Get standard pip size for a symbol (0.0001 for FX, 0.1 for XAUUSD)
   static double  GetPipSize(const string symbol);
   
   // Format double value to string with thousands separators
   static string  FormatMoney(const double amount, const int digits=2);
};

//+------------------------------------------------------------------+
//| NormalizePrice                                                   |
//+------------------------------------------------------------------+
double CUtilities::NormalizePrice(const string symbol, const double price)
{
   double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_size <= 0.0)
   {
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      return NormalizeDouble(price, digits);
   }
   
   // Round to the nearest tick size increment
   return NormalizeDouble(MathRound(price / tick_size) * tick_size, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
//| GetPipSize                                                       |
//+------------------------------------------------------------------+
double CUtilities::GetPipSize(const string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   // For 3-digit and 5-digit symbols, 1 pip = 10 points
   if(digits == 3 || digits == 5)
   {
      return point * 10.0;
   }
   // For Gold (XAUUSD) with 2 digits, 1 pip = 0.1 (10 points)
   if(symbol == "XAUUSD" || symbol == "GOLD")
   {
      return 0.1;
   }
   
   return point;
}

//+------------------------------------------------------------------+
//| PipsToPoints                                                     |
//+------------------------------------------------------------------+
double CUtilities::PipsToPoints(const string symbol, const double pips)
{
   double pip_size = GetPipSize(symbol);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   if(point <= 0.0) return 0.0;
   
   // Convert pips to absolute points
   return (pips * pip_size) / point;
}

//+------------------------------------------------------------------+
//| PointsToPrice                                                    |
//+------------------------------------------------------------------+
double CUtilities::PointsToPrice(const string symbol, const double points)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   return points * point;
}

//+------------------------------------------------------------------+
//| TimeToMinutes                                                    |
//+------------------------------------------------------------------+
int CUtilities::TimeToMinutes(const datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return (dt.hour * 60) + dt.min;
}

//+------------------------------------------------------------------+
//| IsWeekend                                                        |
//+------------------------------------------------------------------+
bool CUtilities::IsWeekend(const datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   // 0 = Saturday, 6 = Sunday in MqlDateTime day_of_week
   return (dt.day_of_week == 0 || dt.day_of_week == 6);
}

//+------------------------------------------------------------------+
//| StringToMinutes                                                  |
//+------------------------------------------------------------------+
int CUtilities::StringToMinutes(const string time_str)
{
   string parts[];
   int count = StringSplit(time_str, ':', parts);
   if(count < 2) return -1;
   
   int hours = (int)StringToInteger(parts[0]);
   int minutes = (int)StringToInteger(parts[1]);
   
   if(hours < 0 || hours > 23 || minutes < 0 || minutes > 59)
   {
      return -1;
   }
   
   return (hours * 60) + minutes;
}

//+------------------------------------------------------------------+
//| FormatMoney                                                      |
//+------------------------------------------------------------------+
string CUtilities::FormatMoney(const double amount, const int digits=2)
{
   string raw = DoubleToString(amount, digits);
   string result = "";
   int dec_pos = StringFind(raw, ".");
   if(dec_pos < 0) dec_pos = StringLen(raw);
   
   int count = 0;
   for(int i = dec_pos - 1; i >= 0; i--)
   {
      result = StringSubstr(raw, i, 1) + result;
      count++;
      if(count % 3 == 0 && i > 0 && StringSubstr(raw, i - 1, 1) != "-")
      {
         result = "," + result;
      }
   }
   
   if(dec_pos < StringLen(raw))
   {
      result = result + StringSubstr(raw, dec_pos);
   }
   
   return result;
}
