//+------------------------------------------------------------------+
//|                                                    1-DMI-XTL.mq5 |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//Inputs

input group "Indicadores";
input int cci_period = 120; // Periodo CCI
input int xtl_param = 37; // Parametro CCI (XTL)
input int dmi_period = 14; // Periodo ADX-DMI
input int macd_fast = 12; // MADCD Rapida
input int macd_slow = 26; // MACD Lenta

input group "Filtros";
input int adx_param = 25; // Parametro ADX
input int cross_period = 2; // Confirmacion de cruce
input int cant_candles = 8; // Cantidad de velas sin operar
input bool filter_days = true; // Filtrar Dias y Horas

input group "RRR";
input int atr_period = 14; // Periodo ATR
input double atrs_sl = 1; // Cantidad de ATRs para SL
input double atrs_tp = 4; // Cantidad de ATRs para TP
input bool exit = true; // Salida Inteligente

input group "Tamaño de posición"
input double lotes_min = 0.1; // Lotaje mínimo
input double risk = 0.005; // Riesgo

input group "Riesgo Variable"
input bool variable_risk = true; // Riesgo Variable
input int ema_atr_period = 200; // Periodo de MA del ATR
input ENUM_MA_METHOD ma_type = MODE_EMA; // Tipo de MA (Para ATR)

//Handlers
int cci_h;
int dmi_h;
int atr_h;
int macd_h;

double cci_array[];
double plusDI_array[];
double minusDI_array[];
double adx[];
double atr[];
double macd[];
double signal_macd[];

CTrade trade;
ulong trade_ticket = 0;

bool time_passed = true;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
//!!!!Validar que los inputs no sean negativos

   cci_h = iCCI(_Symbol, PERIOD_CURRENT, cci_period, PRICE_CLOSE);
   dmi_h = iADX(_Symbol, PERIOD_CURRENT, dmi_period);
   atr_h = iATR(_Symbol, PERIOD_CURRENT, atr_period);
   macd_h = iMACD(_Symbol, PERIOD_CURRENT, macd_fast, macd_slow, 9, PRICE_CLOSE);

   ArraySetAsSeries(cci_array, true);
   ArraySetAsSeries(plusDI_array, true);
   ArraySetAsSeries(minusDI_array, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(macd, true);
   ArraySetAsSeries(signal_macd, true);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {

//Inicializar indicadores

   CopyBuffer(cci_h, 0, 1, 1, cci_array);
   CopyBuffer(dmi_h, 0, 1, 1, adx);
   CopyBuffer(dmi_h, 1, 1, cross_period + 1, plusDI_array);
   CopyBuffer(dmi_h, 2, 1, cross_period + 1, minusDI_array);
   CopyBuffer(atr_h, 0, 1, 1, atr);

//--------Lógica de salida inteligente

   if(!PositionSelectByTicket(trade_ticket) && trade_ticket != 0)
     {
      trade_ticket = 0;
      time_passed = false;
      EventSetTimer(PeriodSeconds() * cant_candles);
     }
   else
      if(PositionSelectByTicket(trade_ticket) && exit)
        {

         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE) PositionGetInteger(POSITION_TYPE);

         if(
            (type == POSITION_TYPE_BUY && CruceBajista())
            || (type == POSITION_TYPE_SELL && CruceAlcista())
         )
           {

            trade.PositionClose(trade_ticket);
            trade_ticket = 0;
            time_passed = false;
            EventSetTimer(PeriodSeconds() * cant_candles);
           }

        }

   MqlDateTime tm = {};
   datetime dt = TimeCurrent(tm);

   if(filter_days && (MalDia(tm.day_of_week) || MalHorario(tm.hour)))
      return;

   if(!time_passed || trade_ticket > 0)
      return;

//---------Lógica de apertura de operaciones

   RevisarCruces();   

   if(cci_array[0] > xtl_param && adx[0] > adx_param && CruceAlcista())
     {
      EjecutarCompra();
     }

   if(cci_array[0] < -xtl_param && adx[0] > adx_param && CruceBajista())
     {
      EjecutarVenta();
     }

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   time_passed = true;
  }

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CruceAlcista()
  {
   CopyBuffer(macd_h, 0, 1, cross_period + 1, macd);
   CopyBuffer(macd_h, 1, 1, cross_period + 1, signal_macd);
   if(macd[cross_period] >= 0)
      return false;
   for(int i = cross_period - 1; i > 0; i--)
     {
      if(macd[i] <= macd[i + 1])
         return false;
     }
   return macd[0] > 0;

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CruceBajista()
  {
   CopyBuffer(macd_h, 0, 1, cross_period + 1, macd);
   CopyBuffer(macd_h, 1, 1, cross_period + 1, signal_macd);
   if(macd[cross_period] <= 0)
      return false;
   for(int i = cross_period -1 ; i > 0; i--)
     {
      if(macd[i] >= macd[i + 1]) //Si DI+ no esta igual o por encima de DI-
         return false;
     }
   return macd[0] < 0;

  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void EjecutarCompra()
  {
   double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

// Calculamos el riesgo efectivo ajustado según el ATR
   double effective_risk;
   AjustarRiesgoPorATR(effective_risk);

   double max_risk = equity * effective_risk;

// SL y TP basados en ATR
   double atr_stop_loss = atrs_sl * atr[0];
   double stop_loss_price = Ask - atr_stop_loss;
   double take_profit_price = Ask + atrs_tp * atr[0];

//---------------------------------ESTO ES UNA GRAN MENTIRA-------------------------------------

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

// Calcular el lotaje permitido: se divide el riesgo máximo (en dinero) entre el riesgo por lote
// y se ajusta dividiendo entre el tamaño del contrato.
   double lotaje_permitido = NormalizeDouble((max_risk / (atr_stop_loss / tick_size)) / tick_value, _Digits);
   double lotaje_final = lotaje_permitido < lotes_min ? lotes_min : lotaje_permitido;

   trade.Buy(NormalizeDouble(lotaje_final, _Digits), _Symbol, Ask, stop_loss_price, take_profit_price, "SUPER MEGA LONG");
   trade_ticket = trade.ResultOrder();

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void EjecutarVenta()
  {
   double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   double effective_risk;
   AjustarRiesgoPorATR(effective_risk);

   double max_risk = equity * effective_risk;

// SL y TP basados en ATR
   double atr_stop_loss = atrs_sl * atr[0];
   double stop_loss_price = Bid + atr_stop_loss;
   double take_profit_price = Bid - atrs_tp * atr[0];

//---------------------------------ESTO ES UNA GRAN MENTIRA-------------------------------------

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

// Calcular el lotaje permitido: se divide el riesgo máximo (en dinero) entre el riesgo por lote
// y se ajusta dividiendo entre el tamaño del contrato.
   double lotaje_permitido = (max_risk / (atr_stop_loss / tick_size)) / tick_value;
   double lotaje_final = lotaje_permitido < lotes_min ? lotes_min : lotaje_permitido;

   if(lotaje_final == lotes_min)
      Print("Lotaje inferior al mínimo");

   trade.Sell(NormalizeDouble(lotaje_final, _Digits), _Symbol, Bid, stop_loss_price, take_profit_price, "SUPER MEGA SHORT");
   trade_ticket = trade.ResultOrder();

  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MalDia(int day)
  {
   return day == 0 || day == 6;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool MalHorario(int time)
  {
   int bad_hours[4] = {16, 52, 52, 52};
   for(int i = 0; i < 4; i++)
     {
      if(time == bad_hours[i])
         return true;
     }

   return false;
  }

// Función para ajustar el riesgo según el ATR y su media móvil.
void AjustarRiesgoPorATR(double &effective_risk)
  {

   if(!variable_risk)
     {
      effective_risk = risk;
      return;
     }

// Copiamos valores del ATR para el período de la MA
   double atr_values[];
   int copied = CopyBuffer(atr_h, 0, 1, ema_atr_period, atr_values);
   if(copied <= 0)
     {
      Print("Error copiando ATR para MA. Se usará el riesgo base.");
      effective_risk = risk;
      return;
     }
   ArraySetAsSeries(atr_values, true);


// Calculamos la MA del ATR
   int ema_atr_h = iMA(_Symbol, PERIOD_CURRENT, ema_atr_period, 1, ma_type, atr_h);
   double ma_atr[];
   CopyBuffer(ema_atr_h, 0, 1, 1, ma_atr);

   double current_atr = atr_values[0];

// Ajustar el riesgo:
// Por defecto usamos el riesgo base (por ejemplo, 0.005 o 0.01)
   effective_risk = risk;
   if(current_atr > ma_atr[0] * 1.05)
     {
      effective_risk = risk * 0.75; // reducir el riesgo en un 25%
     }
   else
      if(current_atr < ma_atr[0] * 0.95)
        {
         effective_risk = risk * 1.25; // aumentar el riesgo en un 25%
        }

   Print("ATR actual: ", current_atr, " | MA ATR: ", ma_atr[0], " | Riesgo efectivo: ", effective_risk);
  }
  
void DibujarCruce(string name, datetime tiempo, double valor_macd, color clr, int arrow_type)
{
   // Si el objeto ya existe, eliminarlo
   if(ObjectFind(0, name) != -1)
      ObjectDelete(0, name);
      
   int macd_window = ChartWindowFind(0, "MACD(" + macd_fast + "," + macd_slow + "," + 9 + ")");

   // Crear la flecha
   if(ObjectCreate(0, name, OBJ_ARROW, macd_window, tiempo, valor_macd))
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrow_type);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);  // Evitar que tape velas
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);

      Print("Señal dibujada en el MACD: ", name, " en ", tiempo, " con valor ", valor_macd);
   }
   else
   {
      Print("Error al crear el objeto: ", name, " | Último error: ", GetLastError());
   }
}

void RevisarCruces()
{
   double macd_values[], signal_values[];
   CopyBuffer(macd_h, 0, 1, 1, macd_values);  // Obtener MACD actual
   CopyBuffer(macd_h, 1, 1, 1, signal_values); // Obtener Señal MACD

   datetime tiempo_actual = iTime(_Symbol, PERIOD_CURRENT, 0);
   double valor_macd = macd_values[0];
  
   if (CruceAlcista())
   {
      string name = "MACD_Buy_" + IntegerToString(tiempo_actual);
      DibujarCruce(name, tiempo_actual, valor_macd, clrLime, 217); // Flecha arriba
   }

   if (CruceBajista())
   {
      string name = "MACD_Sell_" + IntegerToString(tiempo_actual);
      DibujarCruce(name, tiempo_actual, valor_macd, clrRed, 218); // Flecha abajo
   }
}


//+------------------------------------------------------------------+