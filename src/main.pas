{$mode objfpc}{$H+}
{$assertions+}
{$overflowchecks on}
{$rangechecks on}
{$scopedenums on}

program Sevendrl;

uses Util, World, Vision;

procedure enter_raw_mode; cdecl; external;
procedure exit_raw_mode; cdecl; external;
{$L raw_mode.o}

procedure BeginUI;
begin
    enter_raw_mode;
    write(#27'[?1049h');
end;

procedure EndUI;
begin
    write(#27'[?1049l');
    exit_raw_mode;
end;

type
    Color = (default);
    Cell = record
        c: Char;
        fg: Color;
    end;

operator= (const a, b: Cell): Boolean;
begin
    result := (a.c = b.c) and (a.fg = b.fg);
end;

function CharOfTile(const t: Tile): Char;
begin
    case t.kind of
        TileKind.empty: result := ' ';
        TileKind.solid: result := '#';
    end;
end;

function ComputeCell(const map: Map; const player_loc: Vec2; const p: Vec2): Cell;
var t: TilePtr;
begin
    result.fg := Color.default;
    if (p = player_loc) then
        result.c := '@'
    else
    begin
        t := map.GetTile(p);
        if t^.is_visible then
            result.c := CharOfTile(t^)
        else
            result.c := '.';
    end;
end;

procedure MoveCursorExact(const x, y: Int16);
begin
    write(#27'[', y + 1, ';', x + 1, 'H'); // CHA
end;

procedure MoveCursor(const old_x, old_y: Int16; const new_x, new_y: Int16);
var dx, dy: Int16;
begin
    dy := new_y - old_y;
    dx := new_x - old_x;

    if (dy < 0) then
        MoveCursorExact(new_x, new_y)

    else if (dy = 0) then
        if (dx < 0) then
            write(#27'[', -dx, 'D') // CUB
        else if (dx > 0) then
            write(#27'[', dx, 'C') // CUF
        else begin end

    else if (dx = 0) and (dy > 0) then
        if (dy = 1) then
            write(#10)
        else
            write(#27'[', dy, 'B') // CUD

    else if (new_x = 0) and (dy > 0) then
        if (dy = 1) then
            write(#13#10)
        else
            write(#27'[', dy, 'E') // CNL

    else
        MoveCursorExact(new_x, new_y);
end;

type
    Screen = object
    private
        width, height: UInt16;
        cells: array of Cell;
        cursor: Vec2;
    public
        constructor Init(const width_, height_: UInt16);
        procedure Update(const map: Map; const player: Player);
    end;

constructor Screen.Init(const width_, height_: UInt16);
var i: NativeUInt;
begin
    write(#27'[H'#27'[J'); { clear screen & move to top }
    width := width_;
    height := height_;
    SetLength(cells, width * height);
    for i := Low(cells) to High(cells) do
    begin
        cells[i].c := ' ';
        cells[i].fg := Color.default;
    end;
    cursor.x := 0;
    cursor.y := 0;
end;

procedure Screen.Update(const map: Map; const player: Player);
var
    x, y, cx, cy: Int16;
    cur_cell, old_cell: Cell;
    cell_idx: NativeUInt;
begin
    cx := cursor.x;
    cy := cursor.y;
    cell_idx := 0;
    for y := 0 to height - 1 do
        for x := 0 to width - 1 do
        begin
            cur_cell := ComputeCell(map, player.loc, MkVec2(x, y));
            old_cell := cells[cell_idx];
            if (cur_cell <> old_cell) then
            begin
                MoveCursor(cx, cy, x, y);
                { TODO: write color }
                write(cur_cell.c);
                cx := x + 1;
                cy := y;
            end;
            cells[cell_idx] := cur_cell;
            cell_idx := cell_idx + 1;
        end;
    MoveCursor(cx, cy, player.loc.x, player.loc.y);
    cx := player.loc.x;
    cy := player.loc.y;
    cursor.x := cx;
    cursor.y := cy;
end;

type Key = (y, u, h, j, k, l, v, b, n, ctrl_c, other);

function ReadKey: Key;
var
    b: Char;
begin
    read(b);
    // writeln(stderr, ord(b), #13);
    case b of
        #3: result := Key.ctrl_c;
        'y': result := Key.y;
        'u': result := Key.u;
        'h': result := Key.h;
        'j': result := Key.j;
        'k': result := Key.k;
        'l': result := Key.l;
        'v': result := Key.v;
        'b': result := Key.b;
        'n': result := Key.n;
    else
        result := Key.other;
    end;
end;

procedure Main;
const
    WIDTH = 80;
    HEIGHT = 24;
var
    scr: Screen;
    map_: Map;
    p: Player;
    k: Key;
begin
    map_.Init(WIDTH, HEIGHT);
    scr.Init(WIDTH, HEIGHT);
    p := InitPlayer;
    while true do
    begin
        map_.RecomputeVisibility(p);
        scr.Update(map_, p);
        k := ReadKey;
        case k of
            Key.ctrl_c: break;
            Key.h: p.loc.x -= 1;
            Key.j: p.loc.y += 1;
            Key.k: p.loc.y -= 1;
            Key.l: p.loc.x += 1;
            Key.v: p.omniscient := not p.omniscient;
        end;
    end;
end;

begin
    BeginUI;
    try
        Main;
    finally
        EndUI;
    end;
end.
