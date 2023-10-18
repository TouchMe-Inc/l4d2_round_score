
#pragma semicolon               1
#pragma newdecls                required

#include <sdkhooks>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>
#define REQUIRE_PLUGIN


public Plugin myinfo = {
	name = "RoundScore",
	author = "TouchMe",
	description = "The plugin displays the results of the survivor team in chat",
	version = "build_0002"
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
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2)
	{
		strcopy(sErr, iErrLen, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

/**
  * Called when the map starts loading.
  */
public void OnMapStart()
{
	g_bRoundIsLive = false;
}

public void OnPluginStart()
{
	LoadTranslations(TRANSLATIONS);

	// Events.
	HookEvent("player_left_start_area", Event_PlayerLeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("infected_death", Event_InfectedDeath, EventHookMode_Post);

	// Player Commands.
	RegConsoleCmd("sm_score", Cmd_Score);
	RegConsoleCmd("sm_mvp", Cmd_Score);
}

/**
 * Sends new players to the observer team.
 * Called before player change his team.
 */
Action Event_PlayerTeam(Event event, char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(event.GetInt("userid"));

	if (!IsValidClient(iClient)) {
		return Plugin_Continue;
	}

	ClearClientScore(iClient);

	return Plugin_Continue;
}

/**
 * Round start event.
 */
Action Event_PlayerLeftStartArea(Event event, const char[] sName, bool bDontBroadcast)
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

	return Plugin_Continue;
}

/**
 * Round end event.
 */
Action Event_RoundEnd(Event event, const char[] sName, bool bDontBroadcast)
{
	if (g_bRoundIsLive)
	{
		int iTotalPlayers = 0;
		int[] iPlayers = new int[MaxClients];

		for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
		{
			if (!IsClientInGame(iPlayer) || !IsClientSurvivor(iPlayer)) {
				continue;
			}

			iPlayers[iTotalPlayers++] = iPlayer;
		}

		SortCustom1D(iPlayers, iTotalPlayers, Custom1DSort);

		for (int iClient = 1; iClient <= MaxClients; iClient ++)
		{
			if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
				continue;
			}

			PrintToChatScore(iClient, iPlayers, iTotalPlayers);
		}

		g_bRoundIsLive = false;
	}

	return Plugin_Continue;
}

Action Event_PlayerSpawn(Event event, char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(event.GetInt("userid"));

	if (!IsValidClient(iClient) || !IsClientInfected(iClient)) {
		return Plugin_Continue;
	}


	g_iLastHealth[iClient] = GetClientHealth(iClient);

	return Plugin_Continue;
}

/**
 * Registers existing/caused damage.
 */
Action Event_PlayerHurt(Event event, char[] sEventName, bool bDontBroadcast)
{
	int iDamage = event.GetInt("dmg_health");

	int iAttacker = GetClientOfUserId(event.GetInt("attacker"));

	if (!IsValidClient(iAttacker) || !IsClientSurvivor(iAttacker)) {
		return Plugin_Continue;
	}

	int iVictim = GetClientOfUserId(event.GetInt("userid"));

	if (!IsValidClient(iVictim)) {
		return Plugin_Continue;
	}

	if (IsClientSurvivor(iVictim))
	{
		g_iClientStats[iAttacker][STATS_DMG_FF] += iDamage;
		g_iTotalStats[STATS_DMG_FF] += iDamage;
		return Plugin_Continue;
	}

	if (GetClientZombieClass(iVictim) == ZC_TANK) {
		return Plugin_Continue;
	}

	int iRemainingHealth = event.GetInt("health");

	if (iRemainingHealth <= 0) {
		return Plugin_Continue;
	}

	g_iLastHealth[iVictim] = iRemainingHealth;

	g_iClientStats[iAttacker][STATS_DMG_SI] += iDamage;
	g_iTotalStats[STATS_DMG_SI] += iDamage;

	return Plugin_Continue;
}

/**
 * Registers murder.
 */
Action Event_PlayerDeath(Event event, const char[] name, bool bDontBroadcast)
{
	int iVictim = GetClientOfUserId(event.GetInt("userid"));

	if (!IsValidClient(iVictim) || !IsClientInfected(iVictim)) {
		return Plugin_Continue;
	}

	int iKiller = GetClientOfUserId(event.GetInt("attacker"));

	if (!IsValidClient(iKiller) || !IsClientSurvivor(iKiller)) {
		return Plugin_Continue;
	}

	if (GetClientZombieClass(iVictim) == ZC_TANK) {
		return Plugin_Continue;
	}

	if (g_iLastHealth[iVictim])
	{
		g_iClientStats[iKiller][STATS_DMG_SI] += g_iLastHealth[iVictim];
		g_iTotalStats[STATS_DMG_SI] += g_iLastHealth[iVictim];
		g_iLastHealth[iVictim] = 0;
	}

	g_iClientStats[iKiller][STATS_KILL_SI] ++;
	g_iTotalStats[STATS_KILL_SI] ++;

	return Plugin_Continue;
}

/**
 * Surivivor Killed Common Infected.
 */
Action Event_InfectedDeath(Event event, char[] sEventName, bool bDontBroadcast)
{
	int iKiller = GetClientOfUserId(event.GetInt("attacker"));

	if (!IsValidClient(iKiller)) {
		return Plugin_Continue;
	}

	g_iClientStats[iKiller][STATS_KILL_CI] ++;
	g_iTotalStats[STATS_KILL_CI] ++;

	return Plugin_Continue;
}

Action Cmd_Score(int iClient, int iArgs)
{
	if (!IsValidClient(iClient)) {
		return Plugin_Continue;
	}

	if (!g_bRoundIsLive) {
		return Plugin_Handled;
	}

	int iTotalPlayers = 0;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer) || !IsClientSurvivor(iPlayer)) {
			continue;
		}

		iPlayers[iTotalPlayers++] = iPlayer;
	}

	if (!iTotalPlayers) {
		return Plugin_Handled;
	}

	SortCustom1D(iPlayers, iTotalPlayers, Custom1DSort);

	PrintToChatScore(iClient, iPlayers, iTotalPlayers);

	return Plugin_Handled;
}

void PrintToChatScore(int iClient, const int[] iPlayers, int iTotalPlayers)
{
	char sBracketStart[16]; FormatEx(sBracketStart, sizeof(sBracketStart), "%T", "BRACKET_START", iClient);
	char sBracketMiddle[16]; FormatEx(sBracketMiddle, sizeof(sBracketMiddle), "%T", "BRACKET_MIDDLE", iClient);
	char sBracketEnd[16]; FormatEx(sBracketEnd, sizeof(sBracketEnd), "%T", "BRACKET_END", iClient);

	CPrintToChat(iClient, "%s%T", sBracketStart, "TAG", iClient);

	for (int iItem = 0; iItem < iTotalPlayers; iItem ++)
	{
		int iPlayer = iPlayers[iItem];
		float fSIDamageProcent = 0.0;

		if (g_iTotalStats[STATS_DMG_SI] > 0.0) {
			fSIDamageProcent = 100.0 * float(g_iClientStats[iPlayer][STATS_DMG_SI])/float(g_iTotalStats[STATS_DMG_SI]);
		}

		CPrintToChat(iClient, "%s%T",
			(iItem + 1) == iTotalPlayers ? sBracketEnd : sBracketMiddle,
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

int Custom1DSort(int elem1, int elem2, const int[] array, Handle hndl)
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
 * Getting the player's current zombie class.
 *
 * @param iClient       Client index
 *
 * @return              Returns the code of the zombie class
 */
int GetClientZombieClass(int iClient) {
	return GetEntProp(iClient, Prop_Send, "m_zombieClass");
}

/**
 * Survivor team player?
 */
bool IsClientSurvivor(int iClient) {
	return (GetClientTeam(iClient) == TEAM_SURVIVOR);
}
