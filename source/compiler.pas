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

(*
 Need to add command-lines from devCompiler object to
 compiler and linker command lines
*)
unit compiler;

interface

uses
{$IFDEF WIN32}
	Windows, SysUtils, Dialogs, StdCtrls, Controls, ComCtrls, Forms,
	devrun, version, project, utils, prjtypes, Classes, Graphics;
{$ENDIF}
{$IFDEF LINUX}
	SysUtils, QDialogs, QStdCtrls, QComCtrls, QForms,
	devrun, version, project, utils, prjtypes, Classes, QGraphics;
{$ENDIF}

type
	TLogEntryEvent = procedure(const msg: AnsiString) of object;
	TOutputEvent = procedure(const _Line, _Col, _Unit, _Message: AnsiString) of object;
	TResOutputEvent = procedure(const _Line, _Col, _Unit, _Message: AnsiString) of object;
	TSuccessEvent = procedure of object;

	TTarget = (ctNone, ctFile, ctProject);

	TCompiler = class
	private
		fOnLogEntry: TLogEntryEvent;
		fOnOutput: TOutputEvent;
		fOnResOutput: TResOutputEvent;
		fOnSuccess: TSuccessEvent;
		fPerfectDepCheck: Boolean;
		fProject: TProject;
		fSourceFile: AnsiString;
		fRunParams: AnsiString;
		fMakefile : AnsiString;
		fTarget: TTarget;
		fErrCount: integer;
		DoCheckSyntax: Boolean;
		fWarnCount: integer;
		fSingleFile: boolean;
		fOriginalSet : integer;
		procedure DoLogEntry(const msg: AnsiString);
		procedure DoOutput(const s1, s2, s3, s4: AnsiString);
		procedure DoResOutput(const s1, s2, s3, s4: AnsiString);
		function GetMakeFile: AnsiString;
		function GetCompiling: Boolean;
		procedure RunTerminate(Sender: TObject);
		procedure InitProgressForm(const Status: AnsiString);
		procedure EndProgressForm;
		procedure ReleaseProgressForm;
		procedure ProcessProgressForm(const Line: AnsiString);
	public
		procedure BuildMakeFile;
		procedure CheckSyntax;
		procedure Compile(const SingleFile: AnsiString = '');
		procedure Run;
		procedure CompileAndRun;
		function Clean: Boolean;
		function RebuildAll: Boolean;
		function FindDeps(const TheFile: AnsiString): AnsiString;
		procedure SwitchToProjectCompilerSet;
		procedure SwitchToOriginalCompilerSet;

		property Compiling: Boolean read GetCompiling;
		property Project: TProject read fProject write fProject;
		property OnLogEntry: TLogEntryEvent read fOnLogEntry write fOnLogEntry;
		property OnOutput: TOutputEvent read fOnOutput write fOnOutput;
		property OnResOutput: TResOutputEvent read fOnResOutput write fOnResOutput;
		property OnSuccess: TSuccessEvent read fOnSuccess write fOnSuccess;
		property SourceFile: AnsiString read fSourceFile write fSourceFile;
		property PerfectDepCheck: Boolean read fPerfectDepCheck write fPerfectDepCheck;
		property RunParams: AnsiString read fRunParams write fRunParams;
		property MakeFile: AnsiString read GetMakeFile write fMakeFile;
		property Target: TTarget read fTarget write fTarget;
		property WarningCount: integer read fWarnCount;
		property ErrorCount: integer read fErrCount;
		procedure OnAbortCompile(Sender: TObject);
		procedure AbortThread;
	protected
		fCompileParams			: AnsiString;
		fCppCompileParams		: AnsiString;
		fLibrariesParams		: AnsiString;
		fIncludesParams			: AnsiString;
		fCppIncludesParams		: AnsiString;
		fBinDirs				: AnsiString;
		fDevRun					: TDevRun;
		fRunAfterCompileFinish	: boolean;
		fAbortThread			: boolean;

		procedure CreateMakefile;
		procedure CreateStaticMakefile;
		procedure CreateDynamicMakefile;
		procedure GetCompileParams;
		procedure GetLibrariesParams;
		procedure GetIncludesParams;
		procedure LaunchThread(const s, dir : AnsiString);
		procedure ThreadCheckAbort(var AbortThread: boolean);
		procedure OnCompilationTerminated(Sender: TObject);
		procedure OnLineOutput(Sender: TObject; const Line: AnsiString);
		procedure ProcessOutput(const line : AnsiString);
		function NewMakeFile(var F : TextFile) : boolean;
		procedure WriteMakeClean(var F : TextFile);
		procedure WriteMakeObjFilesRules(var F : TextFile);
	end;

implementation

uses
	MultiLangSupport, devcfg, Macros, devExec, main, CompileProgressFrm, StrUtils;

procedure TCompiler.DoLogEntry(const msg: AnsiString);
begin
	if assigned(fOnLogEntry) then
		fOnLogEntry(msg);
end;

procedure TCompiler.DoOutput(const s1, s2, s3, s4: AnsiString);
begin
	if assigned(fOnOutput) then
		fOnOutput(s1, s2, s3, s4);
end;

procedure TCompiler.DoResOutput(const s1, s2, s3, s4: AnsiString);
begin
	if assigned(fOnResOutput) then
		fOnResOutput(s1, s2, s3, s4);
end;

function TCompiler.GetMakeFile: AnsiString;
begin
	if not FileExists(fMakeFile) then
		BuildMakeFile;
	result := fMakefile;
end;

procedure TCompiler.BuildMakeFile;
begin
	if not Assigned(fProject) then begin
		fMakeFile:= '';
		Exit;
	end else if fProject.UseCustomMakefile then begin
		fMakefile:=fProject.CustomMakefile;
		Exit;
	end;

	case fProject.Options.typ of
		dptStat: CreateStaticMakeFile;
		dptDyn: CreateDynamicMakeFile;
	else
		CreateMakeFile;
	end;

	if FileExists(fMakeFile) then
		FileSetDate(fMakefile, DateTimeToFileDate(Now)); // fix the "Clock skew detected" warning ;)
end;

function TCompiler.NewMakeFile(var F : TextFile) : boolean;
var
	ObjResFile, Objects, LinkObjects, Comp_ProgCpp, Comp_Prog, ofile, tfile: AnsiString;
	i: integer;
begin

	// Create OBJ output directory
	SetCurrentDir(fProject.Directory);
	if fProject.Options.ObjectOutput <> '' then
		if not DirectoryExists(fProject.Options.ObjectOutput) then
			CreateDir(fProject.Options.ObjectOutput);

	Objects := '';

	// Create a list of object files
	for i := 0 to Pred(fProject.Units.Count) do begin

		if not fProject.Units[i].Compile and not fProject.Units[i].Link then
			Continue;

		// Only process source files
		tfile := ExtractRelativePath(fProject.FileName,fProject.Units[i].FileName);
		if not (GetFileTyp(tfile) in [utcHead,utcppHead,utResSrc]) then begin
			if fProject.Options.ObjectOutput <> '' then begin

				// ofile = C:\MyProgram\obj\main.o
				ofile := IncludeTrailingPathDelimiter(fProject.Options.ObjectOutput)+ExtractFileName(fProject.Units[i].FileName);
				ofile := GenMakePath(ExtractRelativePath(fProject.FileName, ChangeFileExt(ofile, OBJ_EXT)), True, True);
				Objects := Objects + ' ' + ofile;

				if fProject.Units[i].Link then
					LinkObjects := LinkObjects + ' ' + ofile;
			end else begin
				Objects := Objects + ' ' + GenMakePath(ChangeFileExt(tfile, OBJ_EXT), True, True);
				if fProject.Units[i].Link then
					LinkObjects := LinkObjects + ' ' + GenMakePath1(ChangeFileExt(tfile, OBJ_EXT));
			end;
		end;
	end;

	if Length(fProject.Options.PrivateResource) = 0 then
		ObjResFile := ''
	else begin
		if fProject.Options.ObjectOutput<>'' then begin
			ObjResFile := IncludeTrailingPathDelimiter(fProject.Options.ObjectOutput)+ChangeFileExt(fProject.Options.PrivateResource, RES_EXT);
			ObjResFile := GenMakePath1(ExtractRelativePath(fProject.FileName, ObjResFile));
		end else
			ObjResFile := GenMakePath1(ChangeFileExt(fProject.Options.PrivateResource, RES_EXT));
	end;

	Comp_Prog:= devCompiler.gccName;
	Comp_ProgCpp := devCompiler.gppName;

	GetCompileParams;
	GetLibrariesParams;
	GetIncludesParams;

	// Include special debugging definition
	if (Pos(' -g3',fCompileParams) > 0) then begin
		Comp_ProgCpp := Comp_ProgCpp + ' -D__DEBUG__';
		Comp_Prog := Comp_Prog + ' -D__DEBUG__';
	end;

	fMakefile := fProject.Directory + 'Makefile.win';
	DoLogEntry('Building Makefile "' + fMakefile + '"');
	Assignfile(F, fMakefile);
	try
		Rewrite(F);
	except
		on E: Exception do begin
			MessageDlg('Could not create Makefile "' + fMakefile + '"' + #13#10 + E.Message, mtError, [mbOK], 0);
			result := false;
			exit;
		end;
	end;
	result := true;
	writeln(F, '# Project: ' + fProject.Name);
	writeln(F, '# Makefile created by Dev-C++ ' + DEVCPP_VERSION);
	writeln(F);
	if DoCheckSyntax then begin
		writeln(F, '# This Makefile is written for syntax check!');
		writeln(F, '# Regenerate it if you want to use this Makefile to build.');
		writeln(F);
	end;
	writeln(F, 'CPP      = ' + Comp_ProgCpp);
	writeln(F, 'CC       = ' + Comp_Prog);
	writeln(F, 'WINDRES  = ' + devCompiler.windresName);
	if(ObjResFile <> '') then begin
		writeln(F, 'RES      = ' + ObjResFile);
		writeln(F, 'OBJ      =' + Objects     + ' $(RES)');
		writeln(F, 'LINKOBJ  =' + LinkObjects + ' $(RES)');
	end else begin
		writeln(F, 'OBJ      =' + Objects);
		writeln(F, 'LINKOBJ  =' + LinkObjects);
	end;
	writeln(F, 'LIBS     =' + StringReplace(fLibrariesParams, '\', '/', [rfReplaceAll]));
	writeln(F, 'INCS     =' + StringReplace(fIncludesParams, '\', '/', [rfReplaceAll]));
	writeln(F, 'CXXINCS  =' + StringReplace(fCppIncludesParams, '\', '/', [rfReplaceAll]));
	writeln(F, 'BIN      = ' + GenMakePath1(ExtractRelativePath(Makefile, fProject.Executable)));

	writeln(F, 'CXXFLAGS = $(CXXINCS) ' + fCppCompileParams);
	writeln(F, 'CFLAGS   = $(INCS) ' + fCompileParams);
	writeln(F, 'RM       = rm -f');

	Writeln(F, '');
	if DoCheckSyntax then
		Writeln(F, '.PHONY: all all-before all-after clean clean-custom $(OBJ) $(BIN)')
	else
		Writeln(F, '.PHONY: all all-before all-after clean clean-custom');
	Writeln(F, '');
	Writeln(F, 'all: all-before $(BIN) all-after');
	Writeln(F, '');

	for i := 0 to fProject.Options.MakeIncludes.Count - 1 do
		Writeln(F, 'include ' + GenMakePath1(fProject.Options.MakeIncludes.Strings[i]));

	WriteMakeClean(F);
	writeln(F);
end;

function TCompiler.FindDeps(const TheFile: AnsiString): AnsiString;
var
	Output, Cmd, Includes, GppStr: AnsiString;
	l : TStringList;
	i : integer;
begin
	Result := '';
	OnLineOutput(nil, 'Finding dependencies for file: ' + TheFile);

	if (Assigned(fProject) and fProject.Options.useGPP) or
		(not Assigned(fProject) and (GetFileTyp(TheFile)=utCppSrc)) then
			Includes := fCppIncludesParams + fCppCompileParams
	else
			Includes := fIncludesParams + fCompileParams;

	GppStr := devCompiler.gppName;

	Includes:=StringReplace(Includes, '\', '/', [rfReplaceAll]);
	Cmd := GppStr + ' -MM ' + Includes +' '+ GenMakePath2(ExtractRelativePath(Makefile, TheFile));
	Output := RunAndGetOutput(Cmd, ExtractFileDir(Makefile), nil, nil, nil, True);

	if Length(Output) > 0 then begin
		if (Output[Length(Output)]<>'0') then begin
			// There are error messages
			Result := '';
			Exit;
		end;
		l := TStringList.Create;
		l.Text := Output;
		for i := 0 to l.Count - 2 do
			if system.Pos(': warning:', l[i]) = 0 then
				result := result + l[i];
		l.Free;
		Delete(Result, 1, Pos(': ', Result) + 1);
		Delete(Result, 1, Length(ExtractRelativePath(Makefile, TheFile)) + 1);
		Result := StringReplace(Result, '\ ', ' ', [rfReplaceAll]);
	end;
end;

procedure TCompiler.WriteMakeObjFilesRules(var F: TextFile);
var
	i : integer;
	ShortPath: AnsiString;
	ResIncludes: AnsiString;
	tfile, ofile, ResFiles, tmp: AnsiString;
	windresargs : AnsiString;
begin
	for i := 0 to pred(fProject.Units.Count) do begin
		if not fProject.Units[i].Compile then
			Continue;

		// skip resource files
		if GetFileTyp(fProject.Units[i].FileName) = utResSrc then
			Continue;

		tfile:= fProject.Units[i].FileName;
		if FileSamePath(tfile, fProject.Directory) then
			tfile:= ExtractFileName(tFile)
		else
			tfile:= ExtractRelativePath(Makefile, tfile);

		// Only process source files
		if not (GetFileTyp(tfile) in [utcHead,utcppHead]) then begin
			writeln(F);
			if fProject.Options.ObjectOutput<>'' then begin
				ofile := IncludeTrailingPathDelimiter(fProject.Options.ObjectOutput) + ExtractFileName(fProject.Units[i].FileName);
				ofile := GenMakePath1(ExtractRelativePath(fProject.FileName, ChangeFileExt(ofile, OBJ_EXT)));
			end else
				ofile := GenMakePath1(ChangeFileExt(tfile, OBJ_EXT));

			if DoCheckSyntax then begin
				writeln(F, GenMakePath2(ofile) + ':' + GenMakePath2(tfile));
				if fProject.Units[i].CompileCpp then
					writeln(F, #9 + '$(CPP) -S ' + GenMakePath1(tfile) + ' -o nul $(CXXFLAGS)')
				else
					writeln(F, #9 + '$(CC) -S ' + GenMakePath1(tfile) + ' -o nul $(CFLAGS)');
			end else begin
				if PerfectDepCheck and not fSingleFile then
					writeln(F, GenMakePath2(ofile) + ': ' + GenMakePath2(tfile) + ' ' + FindDeps(fProject.Directory + tfile))
				else
					writeln(F, GenMakePath2(ofile) + ': ' + GenMakePath2(tfile));

				if fProject.Units[i].OverrideBuildCmd and (fProject.Units[i].BuildCmd<>'') then begin
					tmp:=fProject.Units[i].BuildCmd;
					tmp:=StringReplace(tmp, '<CRTAB>', #10#9, [rfReplaceAll]);
					writeln(F, #9+tmp);
				end else begin
					if fProject.Units[i].CompileCpp then
						writeln(F, #9 + '$(CPP) -c ' + GenMakePath1(tfile) + ' -o ' + ofile + ' $(CXXFLAGS)')
					else
						writeln(F, #9 + '$(CC) -c ' + GenMakePath1(tfile) + ' -o ' + ofile + ' $(CFLAGS)');
				end;
			end;
		end;
	end;

	if (Length(fProject.Options.PrivateResource) > 0) then begin
		ResFiles := '';
		ResIncludes := ' ';

		// for some strange reason, lately, windres doesn't like long filenames
		// in "--include-dir"...
		for i := 0 to fProject.Options.ResourceIncludes.Count - 1 do begin
			ShortPath:=GetShortName(fProject.Options.ResourceIncludes[i]);
			// only add include-dir if it is existing dir...
			if ShortPath<>'' then
				ResIncludes := ResIncludes + ' --include-dir ' + GenMakePath1(ShortPath);
		end;

		for i := 0 to fProject.Units.Count - 1 do begin
			if GetFileTyp(fProject.Units[i].FileName) <> utResSrc then
				Continue;
			tfile := ExtractRelativePath(fProject.Executable,fProject.Units[i].FileName);
			if FileExists(GetRealPath(tfile, fProject.Directory)) then
				ResFiles := ResFiles + GenMakePath2(tfile) + ' ';
		end;

		writeln(F);

		if fProject.Options.ObjectOutput<>'' then
			ofile := IncludeTrailingPathDelimiter(fProject.Options.ObjectOutput)+ChangeFileExt(fProject.Options.PrivateResource, RES_EXT)
		else
			ofile := ChangeFileExt(fProject.Options.PrivateResource, RES_EXT);
		ofile := GenMakePath1(ExtractRelativePath(fProject.FileName, ofile));
		tfile := GenMakePath1(ExtractRelativePath(fProject.FileName, fProject.Options.PrivateResource));

		if(ContainsStr(fCompileParams,'-m32')) then
			windresargs := ' -F pe-i386'
		else
			windresargs := '';
		if DoCheckSyntax then begin
			writeln(F, ofile + ':');
			writeln(F, #9 + '$(WINDRES) -i ' + tfile + windresargs + ' --input-format=rc -o nul -O coff' + ResIncludes)
		end else begin
			writeln(F, ofile + ': ' + tfile + ' ' + ResFiles);
			writeln(F, #9 + '$(WINDRES) -i ' + tfile + windresargs + ' --input-format=rc -o ' + ofile + ' -O coff' + ResIncludes);
		end;
	end;
end;

procedure TCompiler.WriteMakeClean(var F: TextFile);
begin
	Writeln(F);
	Writeln(F, 'clean: clean-custom');
	Writeln(F, #9 + '${RM} $(OBJ) $(BIN)');
end;

procedure TCompiler.CreateMakefile;
var
	F : TextFile;
begin
	if not NewMakeFile(F) then
		exit;
	Writeln(F, '$(BIN): $(OBJ)');
	if not DoCheckSyntax then
		if fProject.Options.useGPP then
			writeln(F, #9 + '$(CPP) $(LINKOBJ) -o $(BIN) $(LIBS)')
		else
			writeln(F, #9 + '$(CC) $(LINKOBJ) -o $(BIN) $(LIBS)');
	WriteMakeObjFilesRules(F);
	Flush(F);
	CloseFile(F);
end;

procedure TCompiler.CreateStaticMakefile;
var
	F : TextFile;
begin
	if not NewMakeFile(F) then
		exit;
	writeln(F, '$(BIN): $(LINKOBJ)');
	if not DoCheckSyntax then begin
		writeln(F, #9 + 'ar r $(BIN) $(LINKOBJ)');
		writeln(F, #9 + 'ranlib $(BIN)');
	end;
	WriteMakeObjFilesRules(F);
	Flush(F);
	CloseFile(F);
end;

procedure TCompiler.CreateDynamicMakefile;
var
	F : TextFile;
	pfile,tfile: AnsiString;
begin
	if not NewMakeFile(F) then
		exit;
	writeln(F, 'DLLWRAP=' + devCompiler.dllwrapName);

	pfile:= ExtractFilePath(Project.Executable);
	tfile:= pfile+'lib' + ExtractFileName(Project.Executable);
	if FileSamePath(tfile, Project.Directory) then
		tfile:= ExtractFileName(tFile)
	else
		tfile:= ExtractRelativePath(Makefile, tfile);

	writeln(F, 'DEFFILE=' + GenMakePath1(ChangeFileExt(tfile, '.def')));
	writeln(F, 'STATICLIB=' + GenMakePath1(ChangeFileExt(tfile, LIB_EXT)));
	writeln(F);
	writeln(F, '$(BIN): $(LINKOBJ)');

	if not DoCheckSyntax then begin
		if fProject.Options.useGPP then
			writeln(F, #9 + '$(DLLWRAP) --output-def $(DEFFILE) ' + '--driver-name c++ --implib $(STATICLIB) $(LINKOBJ) $(LIBS) -o $(BIN)')
		else
			writeln(F, #9 + '$(DLLWRAP) --output-def $(DEFFILE) ' + '--implib $(STATICLIB) $(LINKOBJ) $(LIBS) -o $(BIN)');
	end;

	WriteMakeObjFilesRules(F);
	Flush(F);
	CloseFile(F);
end;

procedure TCompiler.GetCompileParams;
var
	I, val: integer;
	option : TCompilerOption;
begin
	with devCompiler do begin
		fCompileParams := '';
		fCppCompileParams := '';

		if Assigned(fProject) and (fTarget = ctProject) then begin
			if Length(fProject.Options.cmdlines.Compiler) > 0 then
				fCompileParams := TrimRight(StringReplace(fProject.Options.cmdlines.Compiler, '_@@_', ' ', [rfReplaceAll]));
			if Length(fProject.Options.cmdlines.CppCompiler) > 0 then
				fCppCompileParams := TrimRight(StringReplace(fProject.Options.cmdlines.CppCompiler, '_@@_', ' ', [rfReplaceAll]));
		end;

		if (Length(devCompiler.CompOpts) > 0) and devCompiler.AddtoComp then begin
			fCompileParams := fCompileParams + ' ' + devCompiler.CompOpts;
			fCppCompileParams := fCppCompileParams + ' ' + devCompiler.CompOpts;
		end;

		for I := 0 to devCompiler.fOptionList.Count - 1 do begin

			option := PCompilerOption(devCompiler.fOptionList[I])^;

			// consider project specific options for the compiler, else global compiler options
			if (Assigned(fProject) and (I<Length(fProject.Options.CompilerOptions))) or (not Assigned(fProject) and (option.optValue > 0)) then begin
				if option.optIsC then begin
					if Assigned(option.optChoices) then begin
						if Assigned(fProject) then
							val := devCompiler.CharToValue(fProject.Options.CompilerOptions[I+1])
						else
							val := option.optValue;
						if (val > 0) and (val < option.optChoices.Count) then
							fCompileParams := fCompileParams + ' ' + option.optSetting + option.optChoices.Values[option.optChoices.Names[val]];
					end else if (Assigned(fProject) and (StrToIntDef(fProject.Options.CompilerOptions[I+1], 0)=1)) or (not Assigned(fProject)) then begin
						fCompileParams := fCompileParams + ' ' + option.optSetting;
					end;
				end;
				if option.optIsCpp then begin
					if Assigned(option.optChoices) then begin
						if Assigned(fProject) then
							val := devCompiler.CharToValue(fProject.Options.CompilerOptions[I+1])
						else
							val := option.optValue;
						if (val > 0) and (val < option.optChoices.Count) then
							fCppCompileParams := fCppCompileParams + ' ' + option.optSetting + option.optChoices.Values[option.optChoices.Names[val]];
					end else if (Assigned(fProject) and (StrToIntDef(fProject.Options.CompilerOptions[I+1], 0)=1)) or (not Assigned(fProject)) then begin
						fCppCompileParams := fCppCompileParams + ' ' + option.optSetting;
					end;
				end;
			end;
		end;
		fCompileParams := Trim(ParseMacros(fCompileParams));
		fCppCompileParams := Trim(ParseMacros(fCppCompileParams));
	end;
end;

procedure TCompiler.CheckSyntax;
begin
	DoCheckSyntax := True;
	Compile;
	DoCheckSyntax := False;
end;

procedure TCompiler.Compile(const SingleFile: AnsiString);
resourcestring
 cCmdLine = '%s "%s" -o "%s" %s %s %s';
 cMakeLine = '%s -f "%s" all';
 cSingleFileMakeLine = '%s -f "%s" %s';
 cMake = ' make';
 cDots = '...';
var
 cmdline : AnsiString;
 s : AnsiString;
 ofile: AnsiString;
begin
	fSingleFile:=SingleFile<>'';
	fRunAfterCompileFinish:= FALSE;
	if Assigned(fDevRun) then begin
		MessageDlg(Lang[ID_MSG_ALREADYCOMP], mtInformation, [mbOK], 0);
		Exit;
	end;

	SwitchToProjectCompilerSet;

	InitProgressForm('Compiling...');

	DoLogEntry(Format('%s: %s', [Lang[ID_COPT_COMPTAB], devCompiler.Sets[devCompiler.CurrentSet]]));

	// Done by buildmakefile
	if not Assigned(fProject) then begin
		GetCompileParams;
		GetLibrariesParams;
		GetIncludesParams;
	end;

	if fTarget = ctProject then begin
		BuildMakeFile;

		if SingleFile <> '' then begin
			if fProject.Options.ObjectOutput<>'' then begin
				ofile := IncludeTrailingPathDelimiter(fProject.Options.ObjectOutput)+ExtractFileName(SingleFile);
				ofile := GenMakePath1(ExtractRelativePath(fProject.FileName, ChangeFileExt(ofile, OBJ_EXT)));
			end else
				ofile := GenMakePath1(ExtractRelativePath(fProject.FileName, ChangeFileExt(SingleFile, OBJ_EXT)));
			cmdline:= format(cSingleFileMakeLine, [devCompiler.makeName, fMakeFile, ofile])
		end else begin
			cmdline:= format(cMakeLine, [devCompiler.makeName, fMakeFile])
		end;

		DoLogEntry(format(Lang[ID_EXECUTING], [cMake + cDots]));
		DoLogEntry(cmdline);

		// Sleep(0) allows other threads to proceed, but we don't want Dev to wait!
		if devCompiler.Delay > 0 then
			Sleep(devCompiler.Delay);
		LaunchThread(cmdline, ExtractFilePath(Project.FileName));
	end else if (GetFileTyp(fSourceFile) = utResSrc) then begin
		s := devCompiler.windresName;
		cmdline := s + ' --input-format=rc -i ' + fSourceFile + ' -o ' + ChangeFileExt(fSourceFile, OBJ_EXT);
		DoLogEntry(format(Lang[ID_EXECUTING], [s + cDots]));
		DoLogEntry(cmdline);
	end else begin
		if (GetFileTyp(fSourceFile) = utcppSrc) then begin
			s := devCompiler.gppName;
			if DoCheckSyntax then
				cmdline:= format(cCmdLine,[s, fSourceFile, 'nul', fCppCompileParams,fCppIncludesParams, fLibrariesParams])
			else
				cmdline:= format(cCmdLine, [s, fSourceFile, ChangeFileExt(fSourceFile, EXE_EXT),fCppCompileParams, fCppIncludesParams, fLibrariesParams]);
			DoLogEntry(format(Lang[ID_EXECUTING], [s + cDots]));
			DoLogEntry(cmdline);
		end else begin
			s := devCompiler.gccName;
			if DoCheckSyntax then
				cmdline:= format(cCmdLine,[s, fSourceFile, 'nul', fCompileParams, fIncludesParams, fLibrariesParams])
			else
				cmdline:= format(cCmdLine,[s, fSourceFile, ChangeFileExt(fSourceFile, EXE_EXT),fCompileParams, fIncludesParams, fLibrariesParams]);
			DoLogEntry(format(Lang[ID_EXECUTING], [s + cDots]));
			DoLogEntry(cmdline);
		end;
		LaunchThread(cmdline, ExtractFilePath(fSourceFile));
	end;
end;

procedure TCompiler.RunTerminate(Sender: TObject);
begin
	Application.Restore;
	MainForm.UpdateAppTitle;
end;

procedure TCompiler.Run;
var
	FileToRun : AnsiString;
	Parameters : AnsiString;
begin
	if fTarget = ctNone then
		exit;
	if fTarget = ctProject then begin
		if fProject.Options.typ = dptStat then
			MessageDlg(Lang[ID_ERR_NOTEXECUTABLE], mtError, [mbOK], 0)
		else if not FileExists(fProject.Executable) then begin
			if devCompiler.Sets.Count > 0 then begin// suggest a compile
				if MessageDlg(Lang[ID_ERR_PROJECTNOTCOMPILEDSUGGEST], mtConfirmation, [mbYes,mbNo], 0) = mrYes then begin
					MainForm.actCompRunExecute(nil); // move this to mainform?
				end;
			end else
				MessageDlg(Lang[ID_ERR_SRCNOTCOMPILED], mtWarning, [mbOK], 0);
		end else if fProject.Options.typ = dptDyn then begin
			if fProject.Options.HostApplication = '' then
				MessageDlg(Lang[ID_ERR_HOSTMISSING], mtWarning, [mbOK], 0)
			else if not FileExists(fProject.Options.HostApplication) then
				MessageDlg(Lang[ID_ERR_HOSTNOTEXIST], mtWarning, [mbOK], 0)
			else begin // execute DLL's host application
				if devData.MinOnRun then
					Application.Minimize;
				devExecutor.ExecuteAndWatch(fProject.Options.HostApplication, fRunParams, ExtractFileDir(fProject.Options.HostApplication), True, INFINITE, RunTerminate);
				MainForm.UpdateAppTitle;
			end;
		end else begin // execute normally

			if devData.ConsolePause and ProgramHasConsole(fProject.Executable) then begin
				Parameters := '"' + fProject.Executable + '" ' + fRunParams;
				FileToRun := devDirs.Exec + 'ConsolePauser.exe';
			end else begin
				Parameters := fRunParams;
				FileToRun := fProject.Executable;
			end;

			if devData.MinOnRun then
				Application.Minimize;
			devExecutor.ExecuteAndWatch(FileToRun, Parameters, ExtractFileDir(fProject.Executable), True, INFINITE, RunTerminate);
			MainForm.UpdateAppTitle;
		end;
	end else begin
		if not FileExists(ChangeFileExt(fSourceFile, EXE_EXT)) then begin
			if devCompiler.Sets.Count > 0 then begin// suggest a compile
				if MessageDlg(Lang[ID_ERR_SRCNOTCOMPILEDSUGGEST], mtConfirmation, [mbYes,mbNo], 0) = mrYes then begin
					MainForm.actCompRunExecute(nil);
				end;
			end else
				MessageDlg(Lang[ID_ERR_SRCNOTCOMPILED], mtWarning, [mbOK], 0);
		end else begin

			if devData.ConsolePause and ProgramHasConsole(ChangeFileExt(fSourceFile, EXE_EXT)) then begin
				Parameters := '"' + ChangeFileExt(fSourceFile, EXE_EXT) + '" ' + fRunParams;
				FileToRun := devDirs.Exec + 'ConsolePauser.exe';
			end else begin
				Parameters := fRunParams;
				FileToRun := ChangeFileExt(fSourceFile, EXE_EXT);
			end;

			if devData.MinOnRun then
				Application.Minimize;
			devExecutor.ExecuteAndWatch(FileToRun, Parameters, ExtractFilePath(fSourceFile), True, INFINITE, RunTerminate);
			MainForm.UpdateAppTitle;
		end;
	end;
end;

procedure TCompiler.CompileAndRun;
begin
	Compile;
	fRunAfterCompileFinish:= TRUE;
end;

function TCompiler.Clean: Boolean;
const
	cCleanLine = '%s clean -f "%s"';
	cmsg = 'make clean';
var
	cmdLine : AnsiString;
begin
	fSingleFile:=True; // fool clean; don't run deps checking since all we do is cleaning
	
	if Assigned(fProject) then begin
		SwitchToProjectCompilerSet;
		DoLogEntry(Format('%s: %s', [Lang[ID_COPT_COMPTAB], devCompiler.Sets[devCompiler.CurrentSet]]));
		Result := True;
		InitProgressForm('Cleaning...');
		BuildMakeFile;
		if not FileExists(fMakefile) then begin
			DoLogEntry(Lang[ID_ERR_NOMAKEFILE]);
			DoLogEntry(Lang[ID_ERR_CLEANFAILED]);
			MessageBox(Application.MainForm.Handle,PAnsiChar(Lang[ID_ERR_NOMAKEFILE]),PAnsiChar(Lang[ID_ERROR]), MB_OK or MB_ICONHAND);
			Result := False;

			SwitchToOriginalCompilerSet;
			Exit;
		end;

		DoLogEntry(Format(Lang[ID_EXECUTING], [cmsg]));
		cmdLine:= Format(cCleanLine, [devCompiler.makeName, fMakeFile]);
		LaunchThread(cmdLine, fProject.Directory);
	end else
		Result := False;
end;

function TCompiler.RebuildAll: Boolean;
const
	cCleanLine = '%s -f "%s" clean all';
	cmsg = 'make clean';
var
	cmdLine : AnsiString;
begin
	fSingleFile := True; // fool rebuild; don't run deps checking since all files will be rebuilt
	Result := True;

	if Assigned(fProject) then begin

		SwitchToProjectCompilerSet;

		InitProgressForm('Rebuilding...');

		DoLogEntry(Format('%s: %s', [Lang[ID_COPT_COMPTAB], devCompiler.Sets[devCompiler.CurrentSet]]));
		BuildMakeFile;
		if not FileExists(fMakefile) then begin

			DoLogEntry(Lang[ID_ERR_NOMAKEFILE]);
			DoLogEntry(Lang[ID_ERR_CLEANFAILED]);
			MessageBox(Application.Handle,PAnsiChar(Lang[ID_ERR_NOMAKEFILE]),PAnsiChar(Lang[ID_ERROR]), MB_OK or MB_ICONERROR);
			Result := False;

			SwitchToOriginalCompilerSet;
			Exit;
		end;

		DoLogEntry(Format(Lang[ID_EXECUTING], [cmsg]));
		cmdLine:= Format(cCleanLine, [devCompiler.makeName, fMakeFile]);
		LaunchThread(cmdLine, fProject.Directory);
	end else
		Compile;
end;

procedure TCompiler.LaunchThread(const s, dir : AnsiString);
begin
	if Assigned(fDevRun) then
		MessageDlg(Lang[ID_MSG_ALREADYCOMP], mtInformation, [mbOK], 0)
	else begin
		fAbortThread:=False;
		fDevRun := TDevRun.Create(true);
		fDevRun.Command := s;
		fDevRun.Directory := dir;
		fDevRun.OnTerminate := OnCompilationTerminated;
		fDevRun.OnLineOutput := OnLineOutput;
		fDevRun.OnCheckAbort := ThreadCheckAbort;
		fDevRun.FreeOnTerminate := True;
		fDevRun.Resume;

		MainForm.UpdateAppTitle;
	end;
end;

procedure TCompiler.ThreadCheckAbort(var AbortThread: boolean);
begin
	AbortThread:=fAbortThread;
end;

procedure TCompiler.AbortThread;
begin
	if not Assigned(fDevRun) then
		Exit;
	fAbortThread:=True;
end;

procedure TCompiler.OnAbortCompile(Sender: TObject);
begin
	if Assigned(fDevRun) then begin
		fAbortThread:=True;
	end else
		ReleaseProgressForm;
end;

procedure TCompiler.OnCompilationTerminated(Sender: TObject);
begin
	DoLogEntry(Lang[ID_EXECUTIONTERM]);

	OnSuccess;

	fDevRun := nil;

	MainForm.UpdateAppTitle;

	EndProgressForm;

	if (fErrCount = 0) and not fAbortThread then begin
		DoLogEntry(Lang[ID_COMPILESUCCESS]);
		if fRunAfterCompileFinish then begin
			fRunAfterCompileFinish:= FALSE;
			ReleaseProgressForm;
			Run;
		end;
	end else if fAbortThread then
		DoLogEntry(Lang[ID_COMPILEABORT]);
	SwitchToOriginalCompilerSet;
end;

procedure TCompiler.OnLineOutput(Sender: TObject; const Line: AnsiString);
var
	List : TStringList;
	I : integer;
begin
	DoLogEntry(Line);

	List := TStringList.Create;
	List.Text := Line;
	for I := 0 to List.Count - 1 do begin
		ProcessOutput(List.Strings[I]);
		if Assigned(CompileProgressForm) then
			ProcessProgressForm(List.Strings[I]);
	end;
	List.Free;
end;

procedure TCompiler.ProcessOutput(const line : AnsiString);
var
	OLine,OCol,OFile,OMsg,S : AnsiString;
	delim : integer;

	procedure GetFileName;
	begin
		OMsg := Trim(OMsg);
		if (Length(OMsg) > 2) and (OMsg[2] = ':') then begin // full file path at start, ignore this one
			delim := FPos(':',OMsg,3);
		end else begin // find first
			delim := FPos(':',OMsg,1);
		end;

		if delim > 0 then begin
			OFile := Copy(OMsg,1,delim-1);
			Delete(OMsg,1,delim);
		end;
	end;

	procedure GetLineNumber;
	begin
		OMsg := Trim(OMsg);
		delim := FPos(':',OMsg,1);
		if delim = 0 then
			delim := FPos(',',OMsg,1);
		if delim > 0 then begin
			OLine := Copy(OMsg,1,delim-1);
			if StrToIntDef(OLine,-1) = -1 then // don't accept
				OLine := ''
			else
				Delete(OMsg,1,delim);
		end;
	end;

	procedure GetColNumber;
	begin
		OMsg := Trim(OMsg);
		delim := FPos(':',OMsg,1);
		if delim = 0 then
			delim := FPos(',',OMsg,1);
		if delim > 0 then begin
			OCol := Copy(OMsg,1,delim-1);
			if StrToIntDef(OLine,-1) = -1 then // don't accept
				OCol := ''
			else
				Delete(OMsg,1,delim);
		end;
	end;

	procedure GetMessageType;
	begin
		OMsg := Trim(OMsg);
		delim := FPos(':',OMsg,1);
		if delim > 0 then begin
			S := Copy(OMsg,1,delim-1);
			if SameStr(S,'error') or SameStr(S,'fatal error') then begin
				Inc(fErrCount);
				Delete(OMsg,1,delim + 1);
				OMsg := '[Error] ' + Trim(OMsg);
			end else if SameStr(S,'warning') then begin
				Inc(fWarnCount);
				Delete(OMsg,1,delim + 1);
				OMsg := '[Warning] ' + Trim(OMsg);
			end else if SameStr(S,'info') then begin
				//Inc(fInfoCount);
				Delete(OMsg,1,delim + 1);
				OMsg := '[Info] ' + Trim(OMsg);
			end else if SameStr(S,'note') then begin
				//Inc(fInfoCount);
				Delete(OMsg,1,delim + 1);
				OMsg := '[Note] ' + Trim(OMsg);
			end;
		end;
	end;

begin

	// Ignore code snippets that GCC 4.8 produces
	if (Length(line) > 0) and (Line[1] = ' ') then // they always start with a space
		Exit;

	OLine := '';
	OCol := '';
	OFile := '';
	OMsg := Trim(Line);

	// Ignore generic 'we are starting program x' messages
	if (Pos(devCompiler.gccName + ' ',Line) = 1) or
       (Pos(devCompiler.gppName + ' ',Line) = 1) or
       (Pos(devCompiler.makeName,Line) = 1) or // ignore all make errors for now
       (Pos(devCompiler.windresName + ' ',Line) = 1) or
       (Pos('rm ',Line) = 1) then Exit;

	// Direction strings
	if StartsStr('In file included from ',OMsg) then begin
		Delete(OMsg,1,Length('In file included from '));

		GetFileName;
		GetLineNumber;
		GetColNumber;

		OMsg := 'In file included from ' + OFile;
		DoOutput(OLine, OCol, OFile, OMsg);
		Exit;
	end else if StartsStr('from ',OMsg) then begin
		Delete(OMsg,1,Length('from '));

		GetFileName;
		GetLineNumber;
		GetColNumber;

		OMsg := '                 from ' + OFile;
		DoOutput(OLine, OCol, OFile, OMsg);
		Exit;
	end;

	GetFileName; // assume regular main.cpp:line:col: message

	if SameStr(OFile,'windres.exe') then begin // resource error
		GetFileName;
		GetLineNumber;
		Inc(fErrCount); // assume it's always an error

		DoResOutput(OLine, '', OFile, OMsg);
	end else begin
		GetLineNumber;
		GetColNumber;
		GetMessageType;

		DoOutput(OLine, OCol, OFile, OMsg);
	end;
end;

procedure TCompiler.GetLibrariesParams;
resourcestring
	cAppendStr = '%s -L"%s"';
var
	i, val : integer;
	option : TCompilerOption;
begin
	// Add libraries
	fLibrariesParams := CommaStrToStr(devCompiler.LibDir, cAppendStr);

	// Add global compiler linker extras
	if devCompiler.AddtoLink and (Length(devCompiler.LinkOpts) > 0) then
		fLibrariesParams := fLibrariesParams + ' ' + devCompiler.LinkOpts;

	// Add libs added via project
	if (fTarget = ctProject) and assigned(fProject) then begin
		for i := 0 to pred(fProject.Options.Libs.Count) do
			fLibrariesParams := format(cAppendStr, [fLibrariesParams, fProject.Options.Libs[i]]);

		// got sick of "symbol 'blah blah' is deprecated"
		if fProject.Options.typ = dptGUI then
			fLibrariesParams:= fLibrariesParams + ' -mwindows';

		// Add project compiler linker extras
		if Length(fProject.Options.cmdLines.Linker) > 0 then
			fLibrariesParams := fLibrariesParams + ' ' + StringReplace(fProject.Options.cmdLines.Linker, '_@@_', ' ', [rfReplaceAll])
	end;

	// Add project settings that need to be passed to the linker
	for I := 0 to devCompiler.fOptionList.Count - 1 do begin
		option := PCompilerOption(devCompiler.fOptionList[I])^;
		if (Assigned(fProject) and (I<Length(fProject.Options.CompilerOptions))) or (not Assigned(fProject) and (option.optValue > 0)) then begin
			if option.optIsLinker then
				if Assigned(option.optChoices) then begin
					if Assigned(fProject) then
						val := devCompiler.CharToValue(fProject.Options.CompilerOptions[I+1])
					else
						val := option.optValue;
					if (val > 0) and (val < option.optChoices.Count) then
						fLibrariesParams := fLibrariesParams + ' ' + option.optSetting + option.optChoices.Values[option.optChoices.Names[val]];
				end else if (Assigned(fProject) and (StrToIntDef(fProject.Options.CompilerOptions[I+1], 0)=1)) or (not Assigned(fProject)) then
					fLibrariesParams := fLibrariesParams + ' ' + option.optSetting;
		end;
	end;
end;

procedure TCompiler.GetIncludesParams;
resourcestring
	cAppendStr = '%s -I"%s"';
var
	i : integer;
begin
	fIncludesParams := CommaStrToStr(devCompiler.CDir, cAppendStr);
	fCppIncludesParams := CommaStrToStr(devCompiler.CppDir, cAppendStr);

	if (fTarget = ctProject) and assigned(fProject) then
		for i := 0 to pred(fProject.Options.Includes.Count) do
			if DirectoryExists(fProject.Options.Includes[i]) then begin
				fIncludesParams := format(cAppendStr, [fIncludesParams, fProject.Options.Includes[i]]);
				fCppIncludesParams := format(cAppendStr, [fCppIncludesParams, fProject.Options.Includes[i]]);
			end;
end;

function TCompiler.GetCompiling: Boolean;
begin
	Result := fDevRun <> nil;
end;

procedure TCompiler.SwitchToOriginalCompilerSet;
begin
	if Assigned(fProject) and (devCompiler.CurrentSet <> fOriginalSet) then
		devCompiler.LoadSet(fOriginalSet);
end;

procedure TCompiler.SwitchToProjectCompilerSet;
begin
	fOriginalSet := devCompiler.CurrentSet;
	if Assigned(fProject) and (devCompiler.CurrentSet <> fProject.Options.CompilerSet) then
		devCompiler.LoadSet(fProject.Options.CompilerSet);
end;

procedure TCompiler.InitProgressForm(const Status: AnsiString);
var
	numsourcefiles,I : integer;
begin

	if not devData.ShowProgress then exit;
	if not Assigned(CompileProgressForm) then
		CompileProgressForm:=TCompileProgressForm.Create(Application);

	with CompileProgressForm do begin

		memoMiniLog.Lines.Clear;
		memoMiniLog.Lines.Add(Format('%s: %s', [Lang[ID_COPT_COMPTAB], devCompiler.Sets[devCompiler.CurrentSet]]));

		btnClose.OnClick:=OnAbortCompile;

		lblCompiler.Caption:=devCompiler.Sets[devCompiler.CurrentSet];
		lblStatus.Caption:=Status;
		lblStatus.Font.Style:=[];

		lblFile.Caption:='';
		lblErr.Caption:='0';
		lblWarn.Caption:='0';

		// Count file types
		if Assigned(fProject) then begin
			numsourcefiles := 0;
			for I:=0 to fProject.Units.Count-1 do
				if GetFileTyp(fProject.Units[I].FileName) in [utcSrc,utcppSrc] then
					Inc(numsourcefiles);

			pb.Min:=0;
			pb.Max:=numsourcefiles + 3; // cleaning + all project units + linking output + private resource
			pb.Position:=0;
		end else
			pb.Max:=1; // just fSourceFile

		starttime:=GetTickCount;
		Show;
	end;

	fWarnCount:=0;
	fErrCount:=0;
end;

procedure TCompiler.ProcessProgressForm(const Line: AnsiString);
var
	filename: AnsiString;
	I : integer;
	Done : boolean;
begin
	Done := false;

	with CompileProgressForm do begin

		lblErr.Caption := IntToStr(fErrCount);
		lblWarn.Caption := IntToStr(fWarnCount);

		// The compiler started to compile a new file
		if StartsStr(devCompiler.gppName + ' ',Line) or StartsStr(devCompiler.gccName + ' ',Line) then begin

			lblStatus.Caption := 'Compiling...';

			filename:='';
			if Assigned(fProject) then begin
				for I:=0 to fProject.Units.Count-1 do begin
					filename:=ExtractFilename(fProject.Units[I].FileName);
					if Pos(filename, Line) > 0 then begin
						lblFile.Caption := filename;
						pb.StepIt;
						memoMiniLog.Lines.Add('Compiling ' + filename + '...');
						Done := true;
						break;
					end;
				end;
			end else if Pos(fSourceFile, Line) > 0 then begin
				lblFile.Caption := fSourceFile;
				pb.StepIt;
				memoMiniLog.Lines.Add('Compiling ' + fSourceFile + '...');
				Done := true;
			end;

			if not Done then begin // might be the linker
				if Assigned(fProject) then
					filename := ExtractFileName(fProject.Executable)
				else
					filename := fSourceFile;

				if ContainsStr(Line,filename) then begin
					lblStatus.Caption := 'Linking...';
					lblFile.Caption := filename;
					pb.StepIt;
					memoMiniLog.Lines.Add('Linking ' + filename + '...');
				end;
			end;
		end else if StartsStr('rm -f ',Line) then begin // Cleaning obj files
			lblStatus.Caption := 'Cleaning...';
			pb.StepIt;
			memoMiniLog.Lines.Add('Cleaning...');
		end else if StartsStr('windres.exe ',Line) and Assigned(fProject) then begin // Resource files
			filename := ExtractFileName(fProject.Options.PrivateResource);
			if ContainsStr(Line,filename) then begin
				lblStatus.Caption := 'Compiling...';
				lblFile.Caption := filename;
				pb.StepIt;
				memoMiniLog.Lines.Add('Compiling ' + filename + '...');
			end;
		end;
	end;
end;

procedure TCompiler.EndProgressForm;
var
	sMsg: AnsiString;
begin
	if Assigned(CompileProgressForm) then begin
		with CompileProgressForm do begin
			pb.Position:=0;
			btnClose.Caption:=Lang[ID_BTN_CLOSE];
			lblErr.Caption:=IntToStr(fErrCount);
			lblWarn.Caption:=IntToStr(fWarnCount);
			if fAbortThread then
				sMsg := 'Aborted'
			else
				sMsg := 'Done in '+FormatFloat('#,###,##0.00', (GetTickCount-starttime)/1000)+' seconds';
			if fErrCount>0 then
				sMsg := sMsg+' with errors.'
			else if fWarnCount>0 then
				sMsg := sMsg+' with warnings.'
			else
				sMsg:=sMsg+'.';
			memoMiniLog.Lines.Add('Done');
			lblStatus.Caption:=sMsg;

			lblStatus.Font.Style:=[fsBold];
			lblFile.Caption:='';
		end;

		if devData.AutoCloseProgress or (fErrCount>0) or (fWarnCount>0) then
			ReleaseProgressForm;
	end;

	if Assigned(fProject) then
		fProject.SaveToLog;
end;

procedure TCompiler.ReleaseProgressForm;
begin
	if Assigned(CompileProgressForm) then begin
		CompileProgressForm.Close; // it's freed on close
		CompileProgressForm:=nil;
	end;
end;

end.

