{
    This file is part of Dev-C++
    Copyright (c) 2004 Bloodshed Software

    Dev-C++ is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    Dev-C++ is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Dev-C++; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
}

unit ProfileAnalysisFm;

interface

uses
{$IFDEF WIN32}
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ComCtrls, ExtCtrls, Spin;
{$ENDIF}
{$IFDEF LINUX}
  SysUtils, Variants, Classes, QGraphics, QControls, QForms,
  QDialogs, QStdCtrls, QComCtrls, QExtCtrls;
{$ENDIF}

type
  TProfileAnalysisForm = class(TForm)
    MainPanel: TPanel;
    PageControl1: TPageControl;
    tabFlat: TTabSheet;
    Splitter2: TSplitter;
    memFlat: TMemo;
    lvFlat: TListView;
    tabGraph: TTabSheet;
    Splitter1: TSplitter;
    memGraph: TMemo;
    lvGraph: TListView;
    tabOpts: TTabSheet;
    FuncHiding: TGroupBox;
    chkHideNotCalled: TCheckBox;
    chkSuppressStatic: TCheckBox;
    Label1: TLabel;
    spnMinCount: TSpinEdit;
    Label2: TLabel;
    btnApply: TButton;
    CustomCommands: TGroupBox;
    chkCustom: TCheckBox;
    editCustom: TEdit;
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormPaint(Sender: TObject);
    procedure lvGraphCustomDrawItem(Sender: TCustomListView;Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure lvFlatCustomDrawItem(Sender: TCustomListView;Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure lvFlatMouseMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
    procedure lvFlatClick(Sender: TObject);
    procedure PageControl1Change(Sender: TObject);
    procedure btnApplyClick(Sender: TObject);
    procedure chkCustomClick(Sender: TObject);
    procedure commandUpdate(Sender: TObject);
  private
    { Private declarations }
    procedure LoadText;
    procedure DoFlat;
    procedure DoGraph;
  public
    { Public declarations }
  end;

var
  ProfileAnalysisForm: TProfileAnalysisForm;

implementation

uses 
{$IFDEF WIN32}
  devcfg, version, utils, main, ShellAPI, StrUtils, MultiLangSupport, CppParser,
  editor;
{$ENDIF}
{$IFDEF LINUX}
  devcfg, version, utils, main, StrUtils, MultiLangSupport, CppParser,
  editor, Types;
{$ENDIF}

{$R *.dfm}

procedure TProfileAnalysisForm.FormShow(Sender: TObject);
begin
  LoadText;
  PageControl1.Visible := False;
end;

procedure TProfileAnalysisForm.FormClose(Sender: TObject;var Action: TCloseAction);
begin
  Action := caFree;
  ProfileAnalysisForm := nil;
end;

procedure TProfileAnalysisForm.DoFlat;
var
  Cmd: string;
  Params: string;
  Dir: string;
  I,J: integer;
  Line: string;
  Parsing: boolean;
  Done: boolean;
  BreakLine: integer;
  spacepos : integer;
begin
	Cmd := '';
	if not chkCustom.Checked then begin
	if (devCompiler.gprofName <> '') then
		Cmd := devCompiler.gprofName
	else
		Cmd := GPROF_PROGRAM;

	Params := ' ' + GPROF_CMD_GENFLAT;

	// Checkbox options
	if not chkHideNotCalled.checked then
		Params := Params + ' -z';
	if chkSuppressStatic.checked then
		Params := Params + ' -a';
	Params := Params + ' -m ' + spnMinCount.Text;

	if Assigned(MainForm.fProject) then begin
		Dir := ExtractFilePath(MainForm.fProject.Executable);
		Params := Params + ' "' + ExtractFileName(MainForm.fProject.Executable) + '"';
	end else begin
		Dir := ExtractFilePath(MainForm.GetEditor.FileName);
		Params := Params + ' "' + ExtractFileName(ChangeFileExt(MainForm.GetEditor.FileName, EXE_EXT)) + '"';
	end;
	end else begin
		Params := editCustom.Text + ' -p';
		if Assigned(MainForm.fProject) then
			Dir := ExtractFilePath(MainForm.fProject.Executable)
		else
			Dir := ExtractFilePath(MainForm.GetEditor.FileName);
	end;

  memFlat.Lines.Text := RunAndGetOutput(Cmd + Params, Dir, nil, nil, nil, False);
  memFlat.SelStart := 0;

  BreakLine := -1;
  I := 0;
  Parsing := False;
  Done := False;
  while (I < memFlat.Lines.Count) and not Done do begin
    Line := memFlat.Lines[I];

    // parse
    if Parsing then begin
      if Trim(Line) = '' then begin
        BreakLine := I;
        Break;
      end;

      with lvFlat.Items.Add do begin
        Caption := Trim(Copy(Line, 55, Length(Line) - 54));

        // remove arguments - if exists
        if AnsiPos('(', Caption) > 0 then
          Data := MainForm.CppParser1.Locate(Copy(Caption, 1, AnsiPos('(', Caption) - 1), True)
        else
          Data := MainForm.CppParser1.Locate(Caption, True);

        // Once here, the function at the END is cut off
        for J:=0 to 5 do begin
        	Line := TrimLeft(Line);
        	spacepos := Pos(' ',Line);
        	SubItems.Add(Trim(Copy(Line, 1, spacepos)));
        	System.Delete(Line,1,spacepos);
        end;
      end;
    end else begin
      Parsing := AnsiStartsText('%', Trim(Line));
      if Parsing then
        Inc(I); // skip over next line too
    end;
    Inc(I);
  end;
  for I := 0 to BreakLine do
    TStringList(memFlat.Lines).Delete(0);
end;

procedure TProfileAnalysisForm.DoGraph;
var
  Cmd: string;
  Params: string;
  Dir: string;
  I,J: integer;
  Line: string;
  Parsing: boolean;
  Done: boolean;
  BreakLine: integer;
  spacepos : integer;
begin
	Cmd := '';
	if not chkCustom.Checked then begin
	if (devCompiler.gprofName <> '') then
		Cmd := devCompiler.gprofName
	else
		Cmd := GPROF_PROGRAM;

	Params := GPROF_CMD_GENMAP;

	// Checkbox options
	if not chkHideNotCalled.checked then
		Params := Params + ' -z';
	if chkSuppressStatic.checked then
		Params := Params + ' -a';
	Params := Params + ' -m ' + spnMinCount.Text;

	if Assigned(MainForm.fProject) then begin
		Dir := ExtractFilePath(MainForm.fProject.Executable);
		Params := Params + ' "' + ExtractFileName(MainForm.fProject.Executable) + '"';
	end else begin
		Dir := ExtractFilePath(MainForm.GetEditor.FileName);
		Params := Params + ' "' + ExtractFileName(ChangeFileExt(MainForm.GetEditor.FileName, EXE_EXT)) + '"';
	end;
	end else begin
		Params := editCustom.Text + ' -q';
		if Assigned(MainForm.fProject) then
			Dir := ExtractFilePath(MainForm.fProject.Executable)
		else
			Dir := ExtractFilePath(MainForm.GetEditor.FileName);
	end;

  memGraph.Lines.Text := RunAndGetOutput(Cmd + Params, Dir, nil, nil, nil, False);
  memGraph.SelStart := 0;

  BreakLine := -1;
  I := 0;
  Parsing := False;
  Done := False;
  while (I < memGraph.Lines.Count) and not Done do begin
    Line := memGraph.Lines[I];

    // parse
    if Parsing then begin
      if Trim(Line) = '' then begin
        BreakLine := I;
        Break;
      end;

      if not AnsiStartsText('---', Line) then begin
        with lvGraph.Items.Add do begin
          Caption := Trim(Copy(Line, 46, Length(Line) - 45));

          // remove arguments - if exists
          if AnsiPos('(', Caption) > 0 then
            Data := MainForm.CppParser1.Locate(Copy(Caption, 1, AnsiPos('(', Caption) - 1), True)
          else
            Data := MainForm.CppParser1.Locate(Caption, True);

        for J:=0 to 5 do begin
        	Line := TrimLeft(Line);
        	spacepos := Pos(' ',Line);
        	SubItems.Add(Trim(Copy(Line, 1, spacepos)));
        	System.Delete(Line,1,spacepos);
        end;
        end;
      end
      else
        lvGraph.Items.Add;
    end
    else
      Parsing := AnsiStartsText('index %', Trim(Line));
    Inc(I);
  end;
  for I := 0 to BreakLine do
    TStringList(memGraph.Lines).Delete(0);
end;

procedure TProfileAnalysisForm.FormPaint(Sender: TObject);
begin
  inherited;
  OnPaint := nil;

  Screen.Cursor := crHourglass;
  Application.ProcessMessages;
  try
    DoFlat;
  except
    lvFlat.Items.Add.Caption := '<Error parsing output>';
  end;

  Application.ProcessMessages;
  try
    DoGraph;
  except
    lvGraph.Items.Add.Caption := '<Error parsing output>';
  end;

  Screen.Cursor := crDefault;
  PageControl1.ActivePage := tabFlat;
  PageControl1.Visible := True;
  lvFlat.SetFocus;
end;

procedure TProfileAnalysisForm.lvFlatCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;var DefaultDraw: Boolean);
begin
  if not (cdsSelected in State) then begin
    if Assigned(Item.Data) then
      Sender.Canvas.Font.Color := clBlue
    else
      Sender.Canvas.Font.Color := clWindowText;
  end;
end;

procedure TProfileAnalysisForm.lvGraphCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;var DefaultDraw: Boolean);
begin
  if not (cdsSelected in State) then begin
    if (Item.SubItems.Count > 0) and (Item.SubItems[0] <> '') then begin
      if Assigned(Item.Data) then
        Sender.Canvas.Font.Color := clBlue
      else
        Sender.Canvas.Font.Color := clWindowText;
    end
    else
      Sender.Canvas.Font.Color := clGray;
  end;

  DefaultDraw := True;
end;

procedure TProfileAnalysisForm.LoadText;
begin
  Caption := Lang[ID_PROF_CAPTION];
  tabFlat.Caption := Lang[ID_PROF_TABFLAT];
  tabGraph.Caption := Lang[ID_PROF_TABGRAPH];
  tabOpts.Caption := Lang[ID_PROF_TABOPTS];
end;

procedure TProfileAnalysisForm.lvFlatMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  It: TListItem;
begin
  with Sender as TListView do begin
    It := GetItemAt(X, Y);
    if Assigned(It) and Assigned(It.Data) then
      Cursor := crHandPoint
    else
      Cursor := crDefault;
  end;
end;

procedure TProfileAnalysisForm.lvFlatClick(Sender: TObject);
var
  It: TListItem;
  P: TPoint;
  e: TEditor;
begin
  P := TListView(Sender).ScreenToClient(Mouse.CursorPos);
  It := TListView(Sender).GetItemAt(P.X, P.Y);
  if Assigned(It) and Assigned(It.Data) then begin
    e := MainForm.GetEditorFromFileName(MainForm.CppParser1.GetImplementationFileName(PStatement(It.Data)));
    if Assigned(e) then begin
      e.GotoLineNr(MainForm.CppParser1.GetImplementationLine(PStatement(It.Data)));
      e.Activate;
    end;
  end;
end;

procedure TProfileAnalysisForm.PageControl1Change(Sender: TObject);
begin
	if PageControl1.ActivePage = tabFlat then
		lvFlat.SetFocus
	else if PageControl1.ActivePage = tabGraph then
		lvGraph.SetFocus
	else
		commandUpdate(nil);
end;

procedure TProfileAnalysisForm.btnApplyClick(Sender: TObject);
begin
	PageControl1.ActivePage := tabFlat;
	lvFlat.Clear;
	DoFlat;
end;

procedure TProfileAnalysisForm.chkCustomClick(Sender: TObject);
begin
	chkHideNotCalled.Enabled := not chkCustom.Checked;
	chkSuppressStatic.Enabled := not chkCustom.Checked;
	spnMinCount.Enabled := not chkCustom.Checked;

	editCustom.Enabled := chkCustom.Checked;
end;

procedure TProfileAnalysisForm.commandUpdate(Sender: TObject);
var
	assembly : string;
begin
	if not chkCustom.Checked then begin
		if (devCompiler.gprofName <> '') then
			assembly := devCompiler.gprofName
		else
			assembly := GPROF_PROGRAM;
		if Assigned(MainForm.fProject) then
			assembly := assembly + ' "' + ExtractFileName(MainForm.fProject.Executable) + '"'
		else
			assembly := assembly + ' "' + ExtractFileName(ChangeFileExt(MainForm.GetEditor.FileName, EXE_EXT)) + '"';
		if not chkHideNotCalled.Checked then
			assembly := assembly + ' -z';
		if chkSuppressStatic.Checked then
			assembly := assembly + ' -s';
		assembly := assembly + ' -m ' + spnMinCount.Text;
		editCustom.Text := assembly;
	end;
end;

end.

