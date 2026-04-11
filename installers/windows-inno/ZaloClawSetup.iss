[Setup]
AppId={{A10E8305-4B81-4C3A-8A53-4E5E8E7D928C}
AppName=ZaloClaw Local Setup (Windows)
AppVersion=0.1.0
AppPublisher=ZaloClaw
DefaultDirName={autopf}\ZaloClawLocalSetup
DefaultGroupName=ZaloClaw Local Setup
OutputDir=.
OutputBaseFilename=ZaloClawLocalSetup-Windows
Compression=lzma
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "scripts\windows-bootstrap.ps1"; DestDir: "{tmp}"; Flags: dontcopy

[Code]
var
  ConfigDirPage: TInputDirWizardPage;
  ProviderPage: TInputOptionWizardPage;
  ApiKeyPage: TInputQueryWizardPage;
  LiteLLMPage: TInputQueryWizardPage;
  CloneModePage: TInputOptionWizardPage;
  OptionsPage: TInputOptionWizardPage;

function SelectedProvider(): String;
begin
  if ProviderPage.SelectedValueIndex = 0 then begin
    Result := 'openai';
    exit;
  end;

  if ProviderPage.SelectedValueIndex = 1 then begin
    Result := 'google';
    exit;
  end;

  Result := 'anthropic';
end;

function SelectedCloneMode(): String;
begin
  if CloneModePage.SelectedValueIndex = 0 then begin
    Result := 'reuse';
    exit;
  end;

  if CloneModePage.SelectedValueIndex = 1 then begin
    Result := 'replace';
    exit;
  end;

  Result := 'fail';
end;

function ProviderKeyArgumentName(const ProviderName: String): String;
begin
  if ProviderName = 'openai' then begin
    Result := '-OpenAIApiKey';
    exit;
  end;

  if ProviderName = 'google' then begin
    Result := '-GoogleApiKey';
    exit;
  end;

  Result := '-AnthropicApiKey';
end;

function EscapeArg(const Value: String): String;
begin
  Result := '"' + Value + '"';
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
end;

procedure InitializeWizard();
begin
  ConfigDirPage := CreateInputDirPage(
    wpSelectDir,
    'OpenClaw Configuration Directory',
    'Choose the OpenClaw config directory',
    'Workspace directory will be derived automatically as <config>\\workspace.',
    False,
    ''
  );
  ConfigDirPage.Add('OpenClaw config directory:');
  ConfigDirPage.Values[0] := ExpandConstant('{userprofile}\\.openclaw_z');

  ProviderPage := CreateInputOptionPage(
    ConfigDirPage.ID,
    'AI Provider',
    'Choose one provider API key',
    'Only one provider key is required for first-run setup.',
    True,
    False
  );
  ProviderPage.Add('OpenAI');
  ProviderPage.Add('Google');
  ProviderPage.Add('Anthropic');
  ProviderPage.SelectedValueIndex := 0;

  ApiKeyPage := CreateInputQueryPage(
    ProviderPage.ID,
    'Provider API Key',
    'Enter the API key for the selected provider',
    'This key is written to zaloclaw-infra/.env.'
  );
  ApiKeyPage.Add('&API Key:', True);

  LiteLLMPage := CreateInputQueryPage(
    ApiKeyPage.ID,
    'LiteLLM Master Key',
    'Enter LITELLM_MASTER_KEY',
    'This key is required for LiteLLM gateway access.'
  );
  LiteLLMPage.Add('&LITELLM_MASTER_KEY:', True);

  CloneModePage := CreateInputOptionPage(
    LiteLLMPage.ID,
    'Repository Handling',
    'Choose how to handle existing repositories',
    'Applies to zaloclaw-ui and zaloclaw-infra if target folders already exist.',
    True,
    False
  );
  CloneModePage.Add('Reuse existing folder');
  CloneModePage.Add('Replace existing folder');
  CloneModePage.Add('Fail and stop setup');
  CloneModePage.SelectedValueIndex := 0;

  OptionsPage := CreateInputOptionPage(
    CloneModePage.ID,
    'Install Options',
    'Choose optional setup behavior',
    'You can change these later by re-running the installer.',
    False,
    False
  );
  OptionsPage.Add('Install missing prerequisites using winget');
  OptionsPage.Add('Start UI after successful infra setup');
  OptionsPage.Values[0] := True;
  OptionsPage.Values[1] := False;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  ProviderName: String;
begin
  Result := True;

  if CurPageID = ConfigDirPage.ID then begin
    if Trim(ConfigDirPage.Values[0]) = '' then begin
      MsgBox('OPENCLAW_CONFIG_DIR is required.', mbError, MB_OK);
      Result := False;
      exit;
    end;
  end;

  if CurPageID = ApiKeyPage.ID then begin
    if Trim(ApiKeyPage.Values[0]) = '' then begin
      ProviderName := SelectedProvider();
      MsgBox('The selected provider API key is required for ' + ProviderName + '.', mbError, MB_OK);
      Result := False;
      exit;
    end;
  end;

  if CurPageID = LiteLLMPage.ID then begin
    if Trim(LiteLLMPage.Values[0]) = '' then begin
      MsgBox('LITELLM_MASTER_KEY is required.', mbError, MB_OK);
      Result := False;
      exit;
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ScriptPath: String;
  Params: String;
  ResultCode: Integer;
  ProviderName: String;
  ProviderArg: String;
begin
  if CurStep <> ssInstall then begin
    exit;
  end;

  ExtractTemporaryFile('windows-bootstrap.ps1');
  ScriptPath := ExpandConstant('{tmp}\windows-bootstrap.ps1');
  ProviderName := SelectedProvider();
  ProviderArg := ProviderKeyArgumentName(ProviderName);

  Params :=
    '-NoProfile -ExecutionPolicy Bypass -File ' + EscapeArg(ScriptPath) + ' ' +
    '-WorkspaceRoot ' + EscapeArg(ExpandConstant('{app}')) + ' ' +
    '-OpenClawConfigDir ' + EscapeArg(ConfigDirPage.Values[0]) + ' ' +
    '-Provider ' + EscapeArg(ProviderName) + ' ' +
    ProviderArg + ' ' + EscapeArg(ApiKeyPage.Values[0]) + ' ' +
    '-LiteLlmMasterKey ' + EscapeArg(LiteLLMPage.Values[0]) + ' ' +
    '-CloneMode ' + EscapeArg(SelectedCloneMode()) + ' ' +
    '-InfraScriptPath ' + EscapeArg(ExpandConstant('{app}\zaloclaw-infra\zaloclaw-docker-setup.ps1'));

  if OptionsPage.Values[0] then begin
    Params := Params + ' -InstallMissingPrerequisites';
  end;

  if OptionsPage.Values[1] then begin
    Params := Params + ' -LaunchUi';
  end;

  Log('Executing bootstrap: powershell.exe ' + Params);

  if not Exec('powershell.exe', Params, ExpandConstant('{app}'), SW_SHOW, ewWaitUntilTerminated, ResultCode) then begin
    RaiseException('Unable to start bootstrap script.');
  end;

  if ResultCode <> 0 then begin
    MsgBox(
      'Windows bootstrap returned exit code ' + IntToStr(ResultCode) + '.' + #13#10 +
      'See setup-state.json in install directory for details.',
      mbError,
      MB_OK
    );
    Abort();
  end;
end;
