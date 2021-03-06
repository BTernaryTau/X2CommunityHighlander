//LWS : Override to allow support for ability-based and other new PCSes.


class UIInventory_Implants extends UIInventory config(GameData); // Config for Issue #170

var localized string m_strNoImplants;

var localized string m_strInstallImplantTitle;
var localized string m_strInstallImplantText;
var localized string m_strReplaceImplantTitle;
var localized string m_strReplaceImplantText;

var array<XComGameState_Item> Implants;

// Variable for Issue #170
var config name PCSRemovalContinentBonusOverride;

simulated function InitScreen(XComPlayerController InitController, UIMovie InitMovie, optional name InitName)
{
	super.InitScreen(InitController, InitMovie, InitName);

	List.OnItemClicked = OnItemSelected;

	ItemCard.SetPosition(1200, 0);
	SetInventoryLayout();
	PopulateData();
}

simulated function PopulateData()
{
	local XComGameState_Item Implant;
	local UIInventory_ListItem ListItem;

	super.PopulateData();

	Implants = XComHQ.GetAllCombatSimsInInventory();
	Implants.Sort(SortImplants);
	Implants.Sort(SortImplantsStatType);
	Implants.Sort(SortItemsTier);

	foreach Implants(Implant)
	{
		UIInventory_ListItem(List.CreateItem(class'UIInventory_ListItem')).InitInventoryListItem(Implant.GetMyTemplate(), Implant.Quantity, Implant.GetReference());
	}

	if(List.ItemCount > 0)
	{
		ListItem = UIInventory_ListItem(List.GetItem(0));
		PopulateItemCard(ListItem.ItemTemplate, ListItem.ItemRef);
	}
	else
	{
		Spawn(class'UIText', ListContainer)
			.InitText('', class'UIUtilities_Text'.static.GetColoredText(m_strNoImplants, eUIState_Header, 24), true)
			.SetPosition(List.x + 20, List.y - 40);
	}

	List.SetSelectedIndex(0);
}

simulated function int SortImplants(XComGameState_Item A, XComGameState_Item B)
{
	local StatBoost StatBoostA, StatBoostB;

	StatBoostA = class'UIUtilities_Strategy'.static.GetStatBoost(A);
	StatBoostB = class'UIUtilities_Strategy'.static.GetStatBoost(B);

	if(StatBoostA.Boost < StatBoostB.Boost) return -1;
	else if(StatBoostA.Boost > StatBoostB.Boost) return 1;
	return 0;
}

simulated function int SortImplantsStatType(XComGameState_Item A, XComGameState_Item B)
{
	local StatBoost StatBoostA, StatBoostB;

	StatBoostA = class'UIUtilities_Strategy'.static.GetStatBoost(A);
	StatBoostB = class'UIUtilities_Strategy'.static.GetStatBoost(B);

	if (StatBoostA.StatType > StatBoostB.StatType) return -1;
	else if (StatBoostA.StatType < StatBoostB.StatType) return 1;
	else return 0;
}

function int SortItemsTier(XComGameState_Item A, XComGameState_Item B)
{	
	local X2ItemTemplate ItemTemplateA, ItemTemplateB;

	ItemTemplateA = A.GetMyTemplate();
	ItemTemplateB = B.GetMyTemplate();

	if (ItemTemplateA.Tier > ItemTemplateB.Tier)
	{
		return 1;
	}
	else if (ItemTemplateA.Tier < ItemTemplateB.Tier)
	{
		return -1;
	}
	else
	{
		return 0;
	}
}

simulated function bool CanEquipImplant(StateObjectReference ImplantRef)
{
	local XComGameState_Unit Unit;
	local XComGameState_Item Implant, ImplantToRemove;
	local array<XComGameState_Item> EquippedImplants;

	// Variables for Issue #171
	local bool bCanEquipImplantResult;
	local XComLWTuple Tuple;

	Implant = XComGameState_Item(History.GetGameStateForObjectID(ImplantRef.ObjectID));

	// Start Issue #171
	bCanEquipImplantResult = true;
	Unit = UIArmory_MainMenu(Movie.Pres.ScreenStack.GetFirstInstanceOf(class'UIArmory_MainMenu')).GetUnit(); // Issue #169 : Changed GetScreen to GetFirstInstanceOf
	if (Unit == none)
	{
		return false; // LWS : Added error-checking code
	}
	if (!class'UIArmory_Implants'.static.CanCycleTo(Unit))
	{
		bCanEquipImplantResult = false; // LWS : added error checking code -- this should be captured by Armory_MainMenu
	}
	// End Issue #171
	EquippedImplants = Unit.GetAllItemsInSlot(eInvSlot_CombatSim);
	ImplantToRemove = XComGameState_Item(`XCOMHISTORY.GetGameStateForObjectID(EquippedImplants[0].ObjectID));
	
	if(class'UIUtilities_Strategy'.static.GetStatBoost(Implant).StatType == 
		class'UIUtilities_Strategy'.static.GetStatBoost(ImplantToRemove).StatType  && 
		class'UIUtilities_Strategy'.static.GetStatBoost(Implant).Boost <= 
		class'UIUtilities_Strategy'.static.GetStatBoost(ImplantToRemove).Boost)
	// Start Issue #171
	{
		bCanEquipImplantResult = false;
	}

	bCanEquipImplantResult = class'UIUtilities_Strategy'.static.GetStatBoost(Implant).StatType != eStat_PsiOffense || Unit.IsPsiOperative();

	Tuple = new class'XComLWTuple';
	Tuple.Id = 'OverrideCanEquipImplant';
	Tuple.Data.Add(1);
	Tuple.Data[0].Kind = XComLWTVBool;
	Tuple.Data[0].b = bCanEquipImplantResult; // the default result

	`XEVENTMGR.TriggerEvent('OverrideCanEquipImplant', Tuple, self);

	return Tuple.Data[0].b;
	// End Issue #171
}

simulated function SelectedItemChanged(UIList ContainerList, int ItemIndex)
{
	local int SlotIndex;
	local XComGameState_Unit Unit;
	local UISoldierHeader SoldierHeader;
	local array<XComGameState_Item> EquippedImplants;
	local XComGameState_Item ImplantToAdd, ImplantToRemove;
	local string Will, Aim, Health, Mobility, Tech, Psi, Dodge; // Issue #172 : added dodge

	super.SelectedItemChanged(ContainerList, ItemIndex);

	Unit = UIArmory_MainMenu(Movie.Pres.ScreenStack.GetFirstInstanceOf(class'UIArmory_MainMenu')).GetUnit(); // Issue #169 : Changed GetScreen to GetFirstInstanceOf
	SoldierHeader = UIArmory_MainMenu(Movie.Pres.ScreenStack.GetFirstInstanceOf(class'UIArmory_MainMenu')).Header; // Issue #169 : Changed GetScreen to GetFirstInstanceOf
	SlotIndex = 0;
	EquippedImplants = Unit.GetAllItemsInSlot(eInvSlot_CombatSim);

	ImplantToAdd = XComGameState_Item(`XCOMHISTORY.GetGameStateForObjectID(Implants[List.SelectedIndex].ObjectID));
	if(SlotIndex < EquippedImplants.Length)
		ImplantToRemove = XComGameState_Item(`XCOMHISTORY.GetGameStateForObjectID(EquippedImplants[SlotIndex].ObjectID));
	
	Will = string( int(Unit.GetCurrentStat( eStat_Will )) ) $ GetStatBoostString(ImplantToAdd, ImplantToRemove, eStat_Will);
	Aim = string( int(Unit.GetCurrentStat( eStat_Offense )) ) $ GetStatBoostString(ImplantToAdd, ImplantToRemove, eStat_Offense);
	Health = string( int(Unit.GetCurrentStat( eStat_HP )) ) $ GetStatBoostString(ImplantToAdd, ImplantToRemove, eStat_HP);
	Mobility = string( int(Unit.GetCurrentStat( eStat_Mobility )) ) $ GetStatBoostString(ImplantToAdd, ImplantToRemove, eStat_Mobility);
	Dodge = string( int(Unit.GetCurrentStat( eStat_Dodge )) ) $ GetStatBoostString(ImplantToAdd, ImplantToRemove, eStat_Dodge); // Isssue #172 : Added dodge
	Tech = string( int(Unit.GetCurrentStat( eStat_Hacking )) ) $ GetStatBoostString(ImplantToAdd, ImplantToRemove, eStat_Hacking);

	if(Unit.IsPsiOperative())
		Psi = string( int(Unit.GetCurrentStat( eStat_PsiOffense )) ) $ GetStatBoostString(ImplantToAdd, ImplantToRemove, eStat_PsiOffense);

	SoldierHeader.SetSoldierStats(Health, Mobility, Aim, Will,, Dodge, Tech, Psi); // Issue #172 : Added dodge
}

simulated function string GetStatBoostString(XComGameState_Item ImplantToAdd, XComGameState_Item ImplantToRemove, ECharStatType StatType)
{
	local int Index, TotalBoost, BoostValue;
	local bool bHasStatBoostBonus;

	if (XComHQ != none)
	{
		bHasStatBoostBonus = XComHQ.SoldierUnlockTemplates.Find('IntegratedWarfareUnlock') != INDEX_NONE;
	}

	if(ImplantToAdd != none)
	{
		Index = ImplantToAdd.StatBoosts.Find('StatType', StatType);
		if (Index != INDEX_NONE)
		{
			BoostValue = ImplantToAdd.StatBoosts[Index].Boost;
			if (bHasStatBoostBonus)
			{				
				if (X2EquipmentTemplate(ImplantToAdd.GetMyTemplate()).bUseBoostIncrement)
					BoostValue += class'X2SoldierIntegratedWarfareUnlockTemplate'.default.StatBoostIncrement;
				else
					BoostValue += Round(BoostValue * class'X2SoldierIntegratedWarfareUnlockTemplate'.default.StatBoostValue);
			}
			TotalBoost += BoostValue;
		}
			
	}

	if(ImplantToRemove != none)
	{
		Index = ImplantToRemove.StatBoosts.Find('StatType', StatType);
		if (Index != INDEX_NONE)
		{
			BoostValue = ImplantToRemove.StatBoosts[Index].Boost;
			if (bHasStatBoostBonus)
			{
				if (X2EquipmentTemplate(ImplantToRemove.GetMyTemplate()).bUseBoostIncrement)
					BoostValue += class'X2SoldierIntegratedWarfareUnlockTemplate'.default.StatBoostIncrement;
				else
					BoostValue += Round(BoostValue * class'X2SoldierIntegratedWarfareUnlockTemplate'.default.StatBoostValue);
			}
			TotalBoost -= BoostValue;
		}
	}

	if(TotalBoost != 0)
		return class'UIUtilities_Text'.static.GetColoredText((TotalBoost > 0 ? "+" : "") $ string(TotalBoost), TotalBoost > 0 ? eUIState_Good : eUIState_Bad);
	else
		return "";
}

simulated function OnItemSelected(UIList ContainerList, int ItemIndex)
{
	local int SlotIndex;
	local XComGameState_Unit Unit;
	local array<XComGameState_Item> EquippedImplants;
	local StateObjectReference ImplantRef;

	ImplantRef = UIInventory_ListItem(ContainerList.GetItem(ItemIndex)).ItemRef;
	
	if (CanEquipImplant(ImplantRef))
	{
		Unit = UIArmory_MainMenu(Movie.Pres.ScreenStack.GetFirstInstanceOf(class'UIArmory_MainMenu')).GetUnit(); // Issue #169 : Changed GetScreen to GetFirstInstanceOf
		SlotIndex = 0;

		EquippedImplants = Unit.GetAllItemsInSlot(eInvSlot_CombatSim);
		
		// Conditional for Issue #170
		if (IsContinentBonusActive ())
		{
			// Skip the popups if the continent bonus for reusing upgrades is active
			if (SlotIndex < EquippedImplants.Length)
				ConfirmImplantRemovalCallback(eUIAction_Accept);
			else
				ConfirmImplantInstallCallback(eUIAction_Accept);
		}
		else
		{
			// Unequip previous implant
			if (SlotIndex < EquippedImplants.Length)
				ConfirmImplantRemoval(EquippedImplants[SlotIndex].GetMyTemplate(), UIInventory_ListItem(List.GetSelectedItem()).ItemTemplate);
			else
				ConfirmImplantInstall(UIInventory_ListItem(List.GetSelectedItem()).ItemTemplate);
		}
	}
	else
		Movie.Pres.PlayUISound(eSUISound_MenuClose);
}

simulated function ConfirmImplantInstall(X2ItemTemplate ImplantTemplate)
{
	local XGParamTag LocTag;
	local TDialogueBoxData DialogData;

	DialogData.eType = eDialog_Alert;
	DialogData.strTitle = m_strInstallImplantTitle;
	DialogData.strAccept = class'UIUtilities_Text'.default.m_strGenericYes;
	DialogData.strCancel = class'UIUtilities_Text'.default.m_strGenericNO;
	DialogData.fnCallback = ConfirmImplantInstallCallback;

	LocTag = XGParamTag(`XEXPANDCONTEXT.FindTag("XGParam"));
	LocTag.StrValue0 = ImplantTemplate.GetItemFriendlyName();
	DialogData.strText = `XEXPAND.ExpandString(m_strInstallImplantText);
	Movie.Pres.UIRaiseDialog(DialogData);
}

simulated function ConfirmImplantRemoval(X2ItemTemplate ImplantToRemove, X2ItemTemplate ImplantToInstall)
{
	local XGParamTag LocTag;
	local TDialogueBoxData DialogData;

	DialogData.eType = eDialog_Alert;
	DialogData.strTitle = m_strReplaceImplantTitle;
	DialogData.strAccept = class'UIUtilities_Text'.default.m_strGenericYes;
	DialogData.strCancel = class'UIUtilities_Text'.default.m_strGenericNO;
	DialogData.fnCallback = ConfirmImplantRemovalCallback;

	LocTag = XGParamTag(`XEXPANDCONTEXT.FindTag("XGParam"));
	LocTag.StrValue0 = ImplantToRemove.GetItemFriendlyName();
	LocTag.StrValue1 = ImplantToInstall.GetItemFriendlyName();
	DialogData.strText = `XEXPAND.ExpandString(m_strReplaceImplantText);
	Movie.Pres.UIRaiseDialog(DialogData);
}

simulated function ConfirmImplantInstallCallback(eUIAction eAction)
{
	if(eAction == eUIAction_Accept)
	{
		InstallImplant();
		CloseScreen();
	}
}

simulated function ConfirmImplantRemovalCallback(eUIAction eAction)
{
	if(eAction == eUIAction_Accept)
	{
		RemoveImplant();
		InstallImplant();
		CloseScreen();
	}
}

simulated function RemoveImplant()
{
	local int SlotIndex;	
	local XComGameState UpdatedState;
	local StateObjectReference UnitRef;
	local XComGameState_Unit UpdatedUnit;
	local array<XComGameState_Item> EquippedImplants;

	UpdatedState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Remove Personal Combat Sim");

	UnitRef = UIArmory_MainMenu(Movie.Pres.ScreenStack.GetFirstInstanceOf(class'UIArmory_MainMenu')).GetUnit().GetReference(); // Issue #169 : Changed GetScreen to GetFirstInstanceOf
	UpdatedUnit = XComGameState_Unit(UpdatedState.CreateStateObject(class'XComGameState_Unit', UnitRef.ObjectID));
	EquippedImplants = UpdatedUnit.GetAllItemsInSlot(eInvSlot_CombatSim);

	SlotIndex = 0;

	if(UpdatedUnit.RemoveItemFromInventory(EquippedImplants[SlotIndex], UpdatedState)) 
	{
		UpdatedState.AddStateObject(UpdatedUnit);

		// Conditional for Issue #170
		if (IsContinentBonusActive ()) // Continent Bonus is letting us reuse upgrades, so put it back into the inventory
		{
			XComHQ = XComGameState_HeadquartersXCom(UpdatedState.CreateStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID));
			UpdatedState.AddStateObject(XComHQ);
			XComHQ.PutItemInInventory(UpdatedState, EquippedImplants[SlotIndex]);
		}
		else
		{
			UpdatedState.RemoveStateObject(EquippedImplants[SlotIndex].ObjectID); // Combat sims cannot be reused
		}

		`GAMERULES.SubmitGameState(UpdatedState);
	}
	else
		`XCOMHISTORY.CleanupPendingGameState(UpdatedState);
}

simulated function InstallImplant()
{
	local XComGameState UpdatedState;
	local StateObjectReference UnitRef;
	local XComGameState_Unit UpdatedUnit;
	local XComGameState_Item UpdatedImplant;
	local XComGameState_HeadquartersXCom UpdatedHQ;

	UpdatedState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Install Personal Combat Sim");

	UnitRef = UIArmory_MainMenu(Movie.Pres.ScreenStack.GetFirstInstanceOf(class'UIArmory_MainMenu')).GetUnit().GetReference(); // Issue #169 : Changed GetScreen to GetFirstInstanceOf
	UpdatedHQ = XComGameState_HeadquartersXCom(UpdatedState.CreateStateObject(class'XComGameState_HeadquartersXCom', XComHQ.ObjectID));
	UpdatedUnit = XComGameState_Unit(UpdatedState.CreateStateObject(class'XComGameState_Unit', UnitRef.ObjectID));
	UpdatedState.AddStateObject(UpdatedHQ);

	UpdatedHQ.GetItemFromInventory(UpdatedState, Implants[List.SelectedIndex].GetReference(), UpdatedImplant);
	
	UpdatedUnit.AddItemToInventory(UpdatedImplant, eInvSlot_CombatSim, UpdatedState);
	UpdatedState.AddStateObject(UpdatedUnit);
	
	`XEVENTMGR.TriggerEvent('PCSApplied', UpdatedUnit, UpdatedImplant, UpdatedState);
	`XSTRATEGYSOUNDMGR.PlaySoundEvent("Strategy_UI_PCS_Equip");

	`GAMERULES.SubmitGameState(UpdatedState);
}

simulated function bool OnUnrealCommand(int cmd, int arg)
{
	// Only pay attention to presses or repeats; ignoring other input types
	// NOTE: Ensure repeats only occur with arrow keys
	if ( !CheckInputIsReleaseOrDirectionRepeat(cmd, arg) )
		return false;

	switch( cmd )
	{
		// OnAccept
`if(`notdefined(FINAL_RELEASE))
		case class'UIUtilities_Input'.const.FXS_KEY_TAB:
`endif
		case class'UIUtilities_Input'.const.FXS_BUTTON_B:
		case class'UIUtilities_Input'.const.FXS_KEY_ESCAPE:
		case class'UIUtilities_Input'.const.FXS_R_MOUSE_DOWN:
			CloseScreen();
			return true;
		case class'UIUtilities_Input'.const.FXS_BUTTON_START:
			`HQPRES.UIPauseMenu( ,true );
			return true;
	}

	return super.OnUnrealCommand(cmd, arg);
}

simulated function CloseScreen()
{
	super.CloseScreen();
	Movie.Pres.PlayUISound(eSUISound_MenuClose);
}

// Start Issue #170
//LWS : new helper function
function bool IsContinentBonusActive ()
{
	local XComGameState_Continent Continent;

	if (PCSRemovalContinentBonusOverride == '')
	{
		return XComHQ.bReuseUpgrades;
	}
	foreach `XCOMHISTORY.IterateByClassType(class'XComGameState_Continent', Continent)
    {
        if(Continent.bContinentBonusActive)
        {
			if (Continent.ContinentBonus == PCSRemovalContinentBonusOverride)
			{
				return true;
			}
		}
	}
	return false;
}
// End Issue #170

defaultproperties
{
	bHideOnLoseFocus = false;
	InputState = eInputState_Consume; // don't cascade input down into the armory
	DisplayTag = "UIBlueprint_Promotion";
	CameraTag = "UIBlueprint_Promotion";
}
