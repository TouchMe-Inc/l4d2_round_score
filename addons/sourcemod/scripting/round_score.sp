
#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <sdkhooks>
#include <colors>


public Plugin myinfo = {
	name = "RoundScore",
	author = "TouchMe",
	description = "The plugin displays the results of the survivor team in chat",
	version = "build_0003",
	url = "https://github.com/TouchMe-Inc/l4d2_round_score"
};


#define TRANSLATIONS            "round_score.phrases"

#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

#define ZC_TANK                 8

#define STATS_KILL_CI           0
#define STATS_KILL_SI           1
#define STATS_DMG_SI            2
#define STATS_DMG_FF            3
#define STATS_MAX_SIZE          4


int
	g_iClientStats[MAXPLAYERS + 1][STATS_MAX_SIZE],
	g_iTotalStats[STATS_MAX_SIZE] = { 0, ... },
	g_iLastHealth[MAXPLAYERS + 1] = { 0, ... };

bool
	g_bRoundIsLive = false;


/**
 * Called before OnPluginStart.
 *
 * @param myself      Handle to the plugin
 * @param bLate       Whether or not the plugin was loaded "late" (after map load)
 * @param sErr        Error message buffer in case load failed
 * @param iErrLen     Maximum number of characters for error message buffer
 * @return            APLRes_Success | APLRes_SilentFailure
 */
public APLRes AskPluginLoad2(Handle myself, bool bLate, char[] sErr, int iErrLen)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(sErr, iErrLen, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

/**
  * Called when the map starts loading.
  */
public void OnMapStart() {
	g_bRoundIsLive = false;
}

public void OnPluginStart()
{
	LoadTranslations(TRANSLATIONS);

	// Events.
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
	HookEvent("player_left_start_area", Event_PlayerLeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("infected_death", Event_InfectedDeath, EventHookMode_Post);

	// Player Commands.
	RegConsoleCmd("sm_score", Cmd_Score);
	RegConsoleCmd("sm_mvp", Cmd_Score);
}

/**
 * Called before player disconnected.
 */
void Event_PlayerDisconnect(Event event, char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!iClient || (IsClientConnected(iClient) && !IsClientInGame(iClient))) {
		return;
	}

	ClearClientScore(iClient);
}

/**
 * Round start event.
 */
void Event_PlayerLeftStartArea(Event event, const char[] sName, bool bDontBroadcast)
{
	for (int iClient = 1; iClient <= MaxClients; iClient ++)
	{
		ClearClientScore(iClient);
	}

	for (int iStats = 0; iStats < STATS_MAX_SIZE; iStats ++)
	{
		g_iTotalStats[iStats] = 0;
	}

	g_bRoundIsLive = true;
}

/**
 * Round end event.
 */
void Event_RoundEnd(Event event, const char[] sName, bool bDontBroadcast)
{
	if (g_bRoundIsLive)
	{
		g_bRoundIsLive = false;

		int iTotalPlayers = 0;
		int[] iPlayers = new int[MaxClients];

		for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
		{
			if (!IsClientInGame(iPlayer)
			|| (!g_iClientStats[iPlayer][STATS_DMG_SI] && !g_iClientStats[iPlayer][STATS_KILL_CI])) {
				continue;
			}

			iPlayers[iTotalPlayers++] = iPlayer;
		}

		SortCustom1D(iPlayers, iTotalPlayers, SortDamage);

		for (int iClient = 1; iClient <= MaxClients; iClient ++)
		{
			if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
				continue;
			}

			if (!iTotalPlayers) {
				CPrintToChat(iClient, "%T%T", "TAG", iClient, "NO_SCORE", iClient);
			}

			else {
				PrintToChatScore(iClient, iPlayers, iTotalPlayers);
			}
		}
	}
}

Action Event_PlayerSpawn(Event event, char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsValidClient(iClient) || !IsClientInfected(iClient)) {
		return Plugin_Continue;
	}


	g_iLastHealth[iClient] = GetClientHealth(iClient);

	return Plugin_Continue;
}

/**
 * Registers existing/caused damage.
 */
void Event_PlayerHurt(Event event, char[] sEventName, bool bDontBroadcast)
{
	int iAttacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (!IsValidClient(iAttacker) || !IsClientSurvivor(iAttacker)) {
		return;
	}

	int iVictim = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsValidClient(iVictim)) {
		return;
	}

	int iDamage = GetEventInt(event, "dmg_health");

	if (IsClientSurvivor(iVictim))
	{
		g_iClientStats[iAttacker][STATS_DMG_FF] += iDamage;
		g_iTotalStats[STATS_DMG_FF] += iDamage;
		return;
	}

	if (GetClientClass(iVictim) == ZC_TANK) {
		return;
	}

	int iRemainingHealth = GetEventInt(event, "health");

	if (iRemainingHealth <= 0) {
		return;
	}

	g_iLastHealth[iVictim] = iRemainingHealth;

	g_iClientStats[iAttacker][STATS_DMG_SI] += iDamage;
	g_iTotalStats[STATS_DMG_SI] += iDamage;
}

/**
 * Registers murder.
 */
void Event_PlayerDeath(Event event, const char[] name, bool bDontBroadcast)
{
	int iVictim = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsValidClient(iVictim) || !IsClientInfected(iVictim)) {
		return;
	}

	int iKiller = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (!IsValidClient(iKiller) || !IsClientSurvivor(iKiller)) {
		return;
	}

	if (GetClientClass(iVictim) == ZC_TANK) {
		return;
	}

	if (g_iLastHealth[iVictim])
	{
		g_iClientStats[iKiller][STATS_DMG_SI] += g_iLastHealth[iVictim];
		g_iTotalStats[STATS_DMG_SI] += g_iLastHealth[iVictim];
		g_iLastHealth[iVictim] = 0;
	}

	g_iClientStats[iKiller][STATS_KILL_SI] ++;
	g_iTotalStats[STATS_KILL_SI] ++;
}

/**
 * Surivivor Killed Common Infected.
 */
void Event_InfectedDeath(Event event, char[] sEventName, bool bDontBroadcast)
{
	int iKiller = GetClientOfUserId(GetEventInt(event, "attacker"));

	if (!IsValidClient(iKiller) || !IsClientSurvivor(iKiller)) {
		return;
	}

	g_iClientStats[iKiller][STATS_KILL_CI] ++;
	g_iTotalStats[STATS_KILL_CI] ++;
}

Action Cmd_Score(int iClient, int iArgs)
{
	if (!iClient) {
		return Plugin_Continue;
	}

	if (!g_bRoundIsLive)
	{
		CPrintToChat(iClient, "%T%T", "TAG", iClient, "ROUND_NOT_LIVE", iClient);
		return Plugin_Handled;
	}

	int iTotalPlayers = 0;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer)
		|| (!g_iClientStats[iPlayer][STATS_DMG_SI] && !g_iClientStats[iPlayer][STATS_KILL_CI])) {
			continue;
		}

		iPlayers[iTotalPlayers++] = iPlayer;
	}

	if (!iTotalPlayers)
	{
		CPrintToChat(iClient, "%T%T", "TAG", iClient, "NO_SCORE", iClient);
		return Plugin_Handled;
	}

	SortCustom1D(iPlayers, iTotalPlayers, SortDamage);

	PrintToChatScore(iClient, iPlayers, iTotalPlayers);

	return Plugin_Handled;
}

void PrintToChatScore(int iClient, const int[] iPlayers, int iTotalPlayers)
{
	CPrintToChat(iClient, "%T%T", "BRACKET_START", iClient, "TAG", iClient);

	for (int iItem = 0; iItem < iTotalPlayers; iItem ++)
	{
		int iPlayer = iPlayers[iItem];
		float fSIDamageProcent = 0.0;

		if (g_iTotalStats[STATS_DMG_SI] > 0.0) {
			fSIDamageProcent = 100.0 * float(g_iClientStats[iPlayer][STATS_DMG_SI]) / float(g_iTotalStats[STATS_DMG_SI]);
		}

		CPrintToChat(iClient, "%s%T",
			(iItem + 1) == iTotalPlayers ? "BRACKET_END" : "BRACKET_MIDDLE", iClient,
			"SCORE", iClient,
			iPlayer,
			g_iClientStats[iPlayer][STATS_KILL_CI],
			g_iClientStats[iPlayer][STATS_KILL_SI],
			g_iClientStats[iPlayer][STATS_DMG_SI],
			fSIDamageProcent,
			g_iClientStats[iPlayer][STATS_DMG_FF]
		);
	}
}

void ClearClientScore(int iClient)
{
	g_iLastHealth[iClient] = 0;

	for (int iStats = 0; iStats < STATS_MAX_SIZE; iStats ++)
	{
		g_iTotalStats[iStats] -= g_iClientStats[iClient][iStats];
		g_iClientStats[iClient][iStats] = 0;
	}
}

int SortDamage(int elem1, int elem2, const int[] array, Handle hndl)
{
	int iDamage1 = g_iClientStats[elem1][STATS_DMG_SI];
	int iDamage2 = g_iClientStats[elem2][STATS_DMG_SI];

	if (iDamage1 > iDamage2) {
		return -1;
	} else if (iDamage1 < iDamage2) {
		return 1;
	}

	return 0;
}

bool IsValidClient(int iClient) {
	return (iClient > 0 && iClient <= MaxClients);
}

/**
 * Infected team player?
 */
bool IsClientInfected(int iClient) {
	return (GetClientTeam(iClient) == TEAM_INFECTED);
}

/**
 * Gets the client L4D1/L4D2 zombie class id.
 *
 * @param client     Client index.
 * @return L4D1      1=SMOKER, 2=BOOMER, 3=HUNTER, 4=WITCH, 5=TANK, 6=NOT INFECTED
 * @return L4D2      1=SMOKER, 2=BOOMER, 3=HUNTER, 4=SPITTER, 5=JOCKEY, 6=CHARGER, 7=WITCH, 8=TANK, 9=NOT INFECTED
 */
int GetClientClass(int iClient) {
	return GetEntProp(iClient, Prop_Send, "m_zombieClass");
}

/**
 * Survivor team player?
 */
bool IsClientSurvivor(int iClient) {
	return (GetClientTeam(iClient) == TEAM_SURVIVOR);
}
