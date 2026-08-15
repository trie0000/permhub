/*
 * セットアップ / 移行スクリプト（権限申請ツール）
 *
 * 使い方:
 *   1. 対象の SharePoint サイトをブラウザで開く（サイト所有者権限が必要）
 *   2. DevTools のコンソールを開く
 *   3. 下の SITE_URL と DO を直す
 *   4. 全文を貼り付けて実行
 *
 * **何度実行しても安全。** 既にあるリスト・列・選択肢・行は飛ばす。
 *
 *   検証環境を作る  … 空サイトに DO を既定のまま実行する。
 *                     これだけでアプリが開いて動くところまで揃う
 *   本番に立てる    … seed / bindMe / adminMe を false にして実行し、
 *                     実データと AdObjectId を手で入れる（docs/deploy.md）
 *   稼働中の更新    … fields だけ true にして実行する。足りない列と選択肢だけを
 *                     足し、リスト作成・索引・一意制約・ダミー投入はしない。
 *                     データが入っているサイトはこれを使う
 *
 * 列の内部名は英語で作られる（表示名は日本語）。
 * Power Fx はこの内部名を参照するので変えないこと。
 */

const SITE_URL = "https://YOUR-TENANT.sharepoint.com/sites/YOUR-SITE";

const DO = {
  fields:   false, // 稼働中のサイトに「足りない列だけ」を追加する（他は何もしない）
  lists:    true,  // リスト 8 本・列・索引・一意制約
  seed:     true,  // ダミーのマスタ（本番では false）
  bindMe:   true,  // 今ログインしている自分を BIND_GID の利用者に紐づける
  adminMe:  true,  // このサイトの Microsoft 365 グループを管理者グループにする
  backfill: false, // 承認機能より前に作ったサイトの後始末（既存申請を完了扱いにする）
};

// bindMe が紐づける先。ダミーの中で権限がいちばん広い人にしておくと確認が早い
const BIND_GID = "1234567";

(async () => {
  const web = SITE_URL.replace(/\/+$/, "");
  const log = (m) => console.log("[PRM] " + m);
  const ctx = await (await fetch(web + "/_api/contextinfo", {
    method: "POST", headers: { Accept: "application/json;odata=verbose" },
    credentials: "same-origin",
  })).json();
  const H = {
    Accept: "application/json;odata=verbose",
    "Content-Type": "application/json;odata=verbose",
    "X-RequestDigest": ctx.d.GetContextWebInformation.FormDigestValue,
  };
  const get = async (u) => (await (await fetch(web + u, {
    headers: { Accept: "application/json;odata=nometadata" }, credentials: "same-origin",
  })).json());
  const post = async (u, body, extra) => {
    const r = await fetch(web + u, {
      method: "POST", credentials: "same-origin",
      headers: { ...H, ...(extra || {}) }, body: JSON.stringify(body),
    });
    if (!r.ok) throw new Error(u + " → " + r.status + " " + (await r.text()).slice(0, 300));
    return r;
  };
  const merge = (u, body) => post(u, body, { "X-HTTP-Method": "MERGE", "IF-MATCH": "*" });
  const L = (t) => `/_api/web/lists/getbytitle('${t}')`;
  const fieldsOf = async (t) =>
    (await get(L(t) + "/fields?$select=InternalName&$top=500")).value.map((f) => f.InternalName);
  const etype = async (t) =>
    (await get(L(t) + "?$select=ListItemEntityTypeFullName")).ListItemEntityTypeFullName;

  // ---- 列定義 --------------------------------------------------------------
  // Options 25 = AddToDefaultContentType | AddFieldInternalNameHint | AddFieldToDefaultView
  // AddFieldInternalNameHint(8) が無いと内部名が日本語エンコードされる
  const OPT = 25;
  const T = (n, d, len) => [n, `<Field Type="Text" DisplayName="${d}" Name="${n}" StaticName="${n}" MaxLength="${len || 255}" />`];
  const N = (n, d) => [n, `<Field Type="Number" DisplayName="${d}" Name="${n}" StaticName="${n}" Decimals="0" />`];
  const B = (n, d, def) => [n, `<Field Type="Boolean" DisplayName="${d}" Name="${n}" StaticName="${n}"><Default>${def ? 1 : 0}</Default></Field>`];
  const C = (n, d, ch, def) => [n, `<Field Type="Choice" DisplayName="${d}" Name="${n}" StaticName="${n}" Format="Dropdown"><CHOICES>${ch.map((c) => `<CHOICE>${c}</CHOICE>`).join("")}</CHOICES>${def ? `<Default>${def}</Default>` : ""}</Field>`, ch];
  const NO = (n, d) => [n, `<Field Type="Note" DisplayName="${d}" Name="${n}" StaticName="${n}" NumLines="6" RichText="FALSE" AppendOnly="FALSE" />`];
  const DT = (n, d) => [n, `<Field Type="DateTime" DisplayName="${d}" Name="${n}" StaticName="${n}" Format="DateTime" />`];

  // 明細の状態。操作は申請まるごとなので、全明細に同じ値が入る
  //   PENDING 未対応 / READY 確認中 / DONE 完了（この時点でマスタに反映）
  //   REJECTED 差し戻し / CANCELED 取り下げ
  // 申請の状態
  //   SUBMITTED 申請済み / INPROGRESS 確認中 / PARTIAL 一部完了
  //   APPLIED 完了 / REJECTED 差し戻し / CANCELED 取り下げ / ERROR 失敗
  const SCHEMA = {
    PRM_Org1: { desc: "権限申請: 組織区分1マスタ", title: "組織区分1コード", fields: [
      T("NameJa", "日本語名称"), T("NameEn", "英語名称"), N("SortOrder", "表示順"),
      B("IsActive", "有効", true),
    ], idx: [] },
    PRM_Org2: { desc: "権限申請: 組織区分2マスタ", title: "組織区分2コード", fields: [
      T("Org1Code", "親の組織区分1コード", 50),
      T("NameJa", "日本語名称"), T("NameEn", "英語名称"), N("SortOrder", "表示順"),
      B("ApExt", "多段階承認要否(外部接続申請)", false),
      B("ApWlan", "多段階承認要否(無線LAN申請)", false),
      B("ApCloud", "多段階承認要否(クラウド申請)", false),
      B("IsActive", "有効", true),
    ], idx: ["Org1Code"] },
    PRM_Users: { desc: "権限申請: 利用者マスタ", title: "キー(メールアドレス)", fields: [
      T("GlobalId", "グローバルID", 50),
      T("FullName", "氏名"), T("Mail", "メールアドレス"), T("Department", "部署名"),
      T("AdObjectId", "ADオブジェクトID", 100), DT("SyncedAt", "AD最終突合日時"),
      B("IsActive", "有効", true),
    ], idx: ["GlobalId", "Mail", "AdObjectId"] },
    PRM_UserOrg1: { desc: "権限申請: 所属 (利用者 × 組織区分1)", title: "キー", fields: [
      T("GlobalId", "グローバルID", 50), T("Org1Code", "組織区分1コード", 50),
      B("IsActive", "有効", true),
    ], idx: ["GlobalId", "Org1Code"] },
    PRM_Grants: { desc: "権限申請: 権限 (1行 = 利用者 × 組織区分1 × 権限)", title: "キー", fields: [
      T("GlobalId", "グローバルID", 50), T("Org1Code", "組織区分1コード", 50),
      C("RoleCode", "権限", ["SECMGR", "CONFORM", "EXTCONN", "WLAN", "CLOUD", "INFOSEC", "EUCLOUD"]),
      C("ScopeType", "範囲", ["ALL", "PICK"], "PICK"),
      NO("Org2Codes", "組織区分2コード (;区切り)"),
      C("CompanyRole", "権限種別", ["PRIMARY", "DEPUTY"]),
      B("IsActive", "有効", true),
      T("LastReqNo", "最終更新申請番号", 50),
    ], idx: ["GlobalId", "Org1Code", "LastReqNo"] },
    PRM_Requests: { desc: "権限申請: 申請ヘッダ", title: "申請番号", fields: [
      C("ReqType", "申請種別", ["ORG1", "ORG2", "USER", "GRANT", "MIXED"]),
      T("TargetKey", "対象キー", 100), T("TargetName", "対象名称"),
      NO("Summary", "申請内容の要約"),
      T("ApplicantId", "申請者グローバルID", 50), T("ApplicantName", "申請者氏名"),
      DT("SubmittedAt", "申請日時"),
      C("Status", "状態", ["SUBMITTED", "INPROGRESS", "PARTIAL", "APPLIED", "REJECTED", "CANCELED", "ERROR"], "SUBMITTED"),
      N("ItemCount", "明細件数"),
      T("Org1Code", "組織区分1コード", 50),
      NO("DecisionNote", "差し戻し・取り下げの理由"),
    ], idx: ["TargetKey", "SubmittedAt", "Org1Code", "Status"] },
    PRM_RequestItems: { desc: "権限申請: 申請明細 (変更前/変更後)", title: "明細キー", fields: [
      T("ReqNo", "申請番号", 50), N("Seq", "連番"),
      C("Operation", "操作", ["ADD", "UPDATE", "DELETE"]),
      C("EntityKind", "対象種別", ["ORG1", "ORG2", "USER", "USERORG1", "GRANT"]),
      T("EntityKey", "対象キー", 200),
      NO("BeforeJson", "変更前"), NO("AfterJson", "変更後"), NO("ChangeText", "変更内容"),
      // 明細は「表示・操作の単位」で束ねる。行そのものは対象 1 件ずつのまま
      // （反映処理を単純に保つため）で、Seq が同じ行が 1 明細として扱われる
      T("GroupKind", "明細の種類", 20), T("GroupKey", "明細の対象", 255),
      C("ItemStatus", "明細の状態", ["PENDING", "READY", "DONE", "REJECTED", "CANCELED"], "PENDING"),
      NO("ItemNote", "差し戻し理由・作業メモ（現在は使わない）"),
      DT("HandledAt", "状態変更日時"), T("HandledBy", "状態変更者", 100),
    ], idx: ["ReqNo", "EntityKey", "ItemStatus"] },
    // テナント固有の値（グループ ID 等）はここに入れ、コードには書かない
    PRM_Config: { desc: "権限申請: 設定 (1 行 = 1 キー)", title: "設定キー", fields: [
      T("Value", "値"), T("Descr", "説明"),
    ], idx: [] },
  };

  // ---- 冪等なヘルパ --------------------------------------------------------
  const have = (await get("/_api/web/lists?$select=Title&$top=500")).value.map((l) => l.Title);

  const ensureList = async (t) => {
    if (have.includes(t)) { log(`${t} は既にある`); return false; }
    await post("/_api/web/lists", {
      __metadata: { type: "SP.List" }, Title: t, BaseTemplate: 100,
      Description: SCHEMA[t].desc, AllowContentTypes: false, ContentTypesEnabled: false,
    });
    have.push(t);
    log(`${t} 作成`);
    return true;
  };
  const fld = (t, i) => L(t) + `/fields/getByInternalNameOrTitle('${i}')`;
  // 選択肢は丸ごと入れ替える（既に入っている値は消さない）
  const ensureChoices = async (t, i, want) => {
    const f = await get(fld(t, i) + "?$select=Choices");
    const now = f.Choices || [];
    const next = now.concat(want.filter((c) => !now.includes(c)));
    if (next.length === now.length) return;
    await merge(fld(t, i), { __metadata: { type: "SP.FieldChoice" }, Choices: { results: next } });
    log(`${t}.${i} に選択肢 ${want.filter((c) => !now.includes(c)).join(",")} を追加`);
  };
  const ensureFields = async (t) => {
    const has = await fieldsOf(t);
    for (const [name, xml, choices] of SCHEMA[t].fields) {
      if (has.includes(name)) { if (choices) await ensureChoices(t, name, choices); continue; }
      await post(L(t) + "/fields/createfieldasxml", {
        parameters: { __metadata: { type: "SP.XmlSchemaFieldCreationInformation" }, SchemaXml: xml, Options: OPT },
      });
      log(`${t}.${name} を追加`);
    }
  };
  const ensureItems = async (t, items) => {
    const type = await etype(t);
    const known = (await get(L(t) + "/items?$select=Title&$top=5000")).value.map((i) => i.Title);
    let n = 0;
    for (const item of items) {
      if (known.includes(item.Title)) continue;
      await post(L(t) + "/items", { __metadata: { type }, ...item });
      n++;
    }
    log(`${t} 投入 ${n} 件 / 既存 ${known.length} 件`);
  };

  // ---- 0. 稼働中のサイトに足りない列だけを足す -----------------------------
  // 既にデータが入っているサイトを新しい版に合わせるときに使う。
  // リストの作成・索引・一意制約・ダミー投入はしない。DO.fields だけ true にして流す。
  if (DO.fields) {
    for (const t of Object.keys(SCHEMA)) {
      const has = await fieldsOf(t).catch(() => null);
      if (!has) { log(`${t} が無いので飛ばす`); continue; }
      await ensureFields(t);
    }
    log("足りない列の追加が終わり");
    return;
  }

  // ---- 1. リスト・列・索引 -------------------------------------------------
  if (DO.lists) {
    for (const t of Object.keys(SCHEMA)) {
      const created = await ensureList(t);
      if (created) await merge(fld(t, "Title"),
        { __metadata: { type: "SP.Field" }, Title: SCHEMA[t].title });
      await ensureFields(t);
      // Title は 一意 + 索引（EnforceUniqueValues は Indexed の後）
      await merge(fld(t, "Title"), { __metadata: { type: "SP.Field" }, Indexed: true });
      await merge(fld(t, "Title"), { __metadata: { type: "SP.Field" }, EnforceUniqueValues: true });
      for (const c of SCHEMA[t].idx)
        await merge(fld(t, c), { __metadata: { type: "SP.Field" }, Indexed: true });
    }
    await ensureItems("PRM_Config", [{
      Title: "AdminGroupId", Value: "",
      Descr: "管理者の Teams(Microsoft 365 グループ) の ID。ここが空なら申請履歴に管理者向けの操作が出ない",
    }]);
    log("リスト・列・索引・一意制約を確認");
  }

  // ---- 2. ダミーのマスタ ---------------------------------------------------
  if (DO.seed) {
    await ensureItems("PRM_Org1", [
      { Title: "B01", NameJa: "東日本ブロック", NameEn: "East Japan Block", SortOrder: 1,
        IsActive: true },
      { Title: "B02", NameJa: "中部ブロック", NameEn: "Central Japan Block", SortOrder: 2,
        IsActive: true },
    ]);

    const o2 = [
      ["A0101", "B01", "北海道支店", "Hokkaido", 1, 1, 1, 0],
      ["A0102", "B01", "東北支店", "Tohoku", 2, 1, 1, 1],
      ["A0103", "B01", "関東支店", "Kanto", 3, 1, 0, 1],
      ["A0104", "B01", "甲信越支店", "Koshinetsu", 4, 0, 0, 0],
      ["A0105", "B01", "北関東事業所", "North Kanto", 5, 1, 1, 1],
      ["A0106", "B01", "東京第一事業所", "Tokyo 1st", 6, 1, 1, 0],
      ["A0201", "B02", "北陸支店", "Hokuriku", 1, 1, 1, 1],
      ["A0202", "B02", "東海支店", "Tokai", 2, 1, 0, 1],
    ];
    await ensureItems("PRM_Org2", o2.map(([c, p, ja, en, s, e, w, cl]) => ({
      Title: c, Org1Code: p, NameJa: ja, NameEn: en, SortOrder: s,
      ApExt: !!e, ApWlan: !!w, ApCloud: !!cl, IsActive: true,
    })));

    const users = [
      ["1234567", "検証 太郎", "情報システム部"], ["A234567", "山田 花子", "総務部"],
      ["2345678", "佐藤 一郎", "生産技術部"], ["3456789", "鈴木 次郎", "品質保証部"],
      ["B345678", "田中 三郎", "情報システム部"], ["4567890", "高橋 美咲", "経営企画部"],
      ["5678901", "伊藤 健太", "製造部"], ["C456789", "渡辺 由美", "調達部"],
      ["6789012", "中村 大輔", "開発部"], ["7890123", "小林 彩", "人事部"],
      ["D567890", "加藤 隆", "情報システム部"], ["8901234", "吉田 直樹", "設備管理部"],
    ];
    const romaji = ["kensho.taro", "yamada.hanako", "sato.ichiro", "suzuki.jiro",
      "tanaka.saburo", "takahashi.misaki", "ito.kenta", "watanabe.yumi",
      "nakamura.daisuke", "kobayashi.aya", "kato.takashi", "yoshida.naoki"];
    await ensureItems("PRM_Users", users.map(([g, n, d], i) => ({
      Title: g, FullName: n, Mail: romaji[i] + "@example.com", Department: d, IsActive: true,
    })));

    const memb = users.map(([g]) => [g, "B01"]).concat([["1234567", "B02"], ["2345678", "B02"]]);
    await ensureItems("PRM_UserOrg1", memb.map(([g, o]) => ({
      Title: `${g}#${o}`, GlobalId: g, Org1Code: o, IsActive: true,
    })));

    const grants = [
      ["1234567", "B01", "SECMGR", "ALL", "", ""],
      ["1234567", "B01", "EXTCONN", "ALL", "", "PRIMARY"],
      ["1234567", "B01", "INFOSEC", "ALL", "", ""],
      ["A234567", "B01", "EXTCONN", "PICK", ";A0101;A0103;", "DEPUTY"],
      ["A234567", "B01", "CONFORM", "PICK", ";A0101;A0102;", ""],
      ["2345678", "B01", "EXTCONN", "PICK", ";A0102;A0103;A0105;", "PRIMARY"],
      ["2345678", "B01", "WLAN", "PICK", ";A0102;", "PRIMARY"],
      ["3456789", "B01", "WLAN", "ALL", "", "DEPUTY"],
      ["B345678", "B01", "CLOUD", "ALL", "", "PRIMARY"],
      ["B345678", "B01", "INFOSEC", "PICK", ";A0102;", ""],
      ["4567890", "B01", "CONFORM", "ALL", "", ""],
      ["5678901", "B01", "EXTCONN", "PICK", ";A0105;A0106;", "DEPUTY"],
      ["C456789", "B01", "CLOUD", "PICK", ";A0102;A0103;", "DEPUTY"],
      ["6789012", "B01", "SECMGR", "PICK", ";A0105;", ""],
      ["7890123", "B01", "WLAN", "PICK", ";A0101;A0105;", "PRIMARY"],
      ["D567890", "B01", "INFOSEC", "ALL", "", ""],
      ["8901234", "B01", "CONFORM", "PICK", ";A0106;", ""],
    ];
    await ensureItems("PRM_Grants", grants.map(([g, o, r, s, codes, cr]) => {
      const it = { Title: `${g}#${o}#${r}`, GlobalId: g, Org1Code: o, IsActive: true,
        RoleCode: r, ScopeType: s, Org2Codes: codes };
      if (cr) it.CompanyRole = cr;
      return it;
    }));
  }

  // ---- 3. 自分をマスタに紐づける -------------------------------------------
  // アプリは Office365ユーザー.MyProfileV2().id と PRM_Users.AdObjectId を突き合わせる。
  // ここが空だとログイン者を特定できず、所属が 0 件になって画面が空で開く
  if (DO.bindMe) {
    const props = (await get(
      "/_api/SP.UserProfiles.PeopleManager/GetMyProperties?$select=UserProfileProperties"
    )).UserProfileProperties || [];
    const oid = (props.find((p) => p.Key === "msOnline-ObjectId") || {}).Value || "";
    if (!/^[0-9a-f-]{36}$/i.test(oid)) {
      log("⚠ 自分の Entra ID オブジェクト ID を取得できなかった。PRM_Users.AdObjectId は手で入れる");
    } else {
      const row = (await get(
        L("PRM_Users") + `/items?$select=Id,AdObjectId&$filter=Title eq '${BIND_GID}'`)).value[0];
      if (!row) {
        log(`⚠ PRM_Users に ${BIND_GID} が無い。BIND_GID を直すか、先に seed を実行する`);
      } else if (row.AdObjectId === oid) {
        log(`${BIND_GID} は既に自分に紐づいている`);
      } else {
        await merge(L("PRM_Users") + `/items(${row.Id})`,
          { __metadata: { type: await etype("PRM_Users") }, AdObjectId: oid, SyncedAt: new Date().toISOString() });
        log(`${BIND_GID} を自分に紐づけた（アプリはこの人として動く）`);
      }
    }
  }

  // ---- 4. このサイトのグループを管理者にする -------------------------------
  if (DO.adminMe) {
    const gid = String((await get("/_api/site?$select=GroupId")).GroupId || "");
    if (!/^[0-9a-f-]{36}$/i.test(gid) || gid.startsWith("00000000")) {
      log("⚠ このサイトは Microsoft 365 グループに紐づいていない。AdminGroupId は手で入れる");
    } else {
      const row = (await get(
        L("PRM_Config") + "/items?$select=Id,Value&$filter=Title eq 'AdminGroupId'")).value[0];
      if (!row) log("⚠ PRM_Config に AdminGroupId の行が無い。lists を true にして実行する");
      else if (row.Value === gid) log("AdminGroupId は既にこのサイトのグループ");
      else {
        await merge(L("PRM_Config") + `/items(${row.Id})`,
          { __metadata: { type: await etype("PRM_Config") }, Value: gid });
        log("AdminGroupId にこのサイトのグループを設定（このチームのメンバーが管理者）");
      }
    }
  }

  // ---- 5. 承認機能より前に作ったサイトの後始末 -----------------------------
  if (DO.backfill) {
    // 当時は「申請した時点でマスタに反映」だったので、状態の無い明細は完了扱いにする
    const itemType = await etype("PRM_RequestItems");
    const blanks = (await get(L("PRM_RequestItems") + "/items?$select=Id,ItemStatus&$top=5000"))
      .value.filter((i) => !i.ItemStatus);
    for (const it of blanks)
      await merge(L("PRM_RequestItems") + `/items(${it.Id})`,
        { __metadata: { type: itemType }, ItemStatus: "DONE" });
    log(`既存明細 ${blanks.length} 件を DONE にした`);

    // 理由は明細ごとに持っていた。申請 1 本につき理由は 1 つなので、
    // 最初に見つかった ItemNote を DecisionNote に写す（明細側は消さずに残す）
    const reqType = await etype("PRM_Requests");
    const noted = (await get(L("PRM_RequestItems") + "/items?$select=ReqNo,ItemNote&$top=5000"))
      .value.filter((i) => i.ItemNote);
    const byReq = {};
    for (const i of noted) if (!byReq[i.ReqNo]) byReq[i.ReqNo] = i.ItemNote;
    let moved = 0;
    for (const [no, note] of Object.entries(byReq)) {
      const r = (await get(
        L("PRM_Requests") + `/items?$select=Id,DecisionNote&$filter=Title eq '${no}'`)).value[0];
      if (!r || r.DecisionNote) continue;
      await merge(L("PRM_Requests") + `/items(${r.Id})`,
        { __metadata: { type: reqType }, DecisionNote: note });
      moved++;
    }
    log(`差し戻し理由 ${moved} 件を申請側へ移した`);
  }

  log("完了。次はアプリを作る → docs/deploy.md 手順 4 から");
})().catch((e) => console.error("[PRM] 失敗:", e));
