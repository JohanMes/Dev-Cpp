object CodeComplForm: TCodeComplForm
  Left = 332
  Top = 305
  BorderIcons = []
  BorderStyle = bsNone
  ClientHeight = 286
  ClientWidth = 472
  Color = clBtnFace
  Constraints.MinHeight = 128
  Constraints.MinWidth = 256
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  FormStyle = fsStayOnTop
  KeyPreview = True
  OldCreateOrder = False
  OnDeactivate = FormDeactivate
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 13
  object lbCompletion: TListBox
    Left = 0
    Top = 0
    Width = 472
    Height = 286
    Style = lbOwnerDrawFixed
    Align = alClient
    BevelInner = bvNone
    BevelOuter = bvNone
    BorderStyle = bsNone
    ItemHeight = 16
    TabOrder = 0
    OnDblClick = lbCompletionDblClick
    OnDrawItem = lbCompletionDrawItem
    OnKeyPress = lbCompletionKeyPress
  end
end
