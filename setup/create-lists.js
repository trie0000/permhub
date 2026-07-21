/*
 * SharePoint リスト作成スクリプト（権限申請ツール）
 *
 * 使い方:
 *   1. 対象の SharePoint サイトをブラウザで開く（サイト所有者権限が必要）
 *   2. DevTools のコンソールを開く
 *   3. 下の SITE_URL を対象サイトに書き換える
 *   4. 全文を貼り付けて実行
 *
 * 作られるもの（docs/data-model.md 参照）:
 *   PRM_Org1        組織区分1マスタ
 *   PRM_Org2        組織区分2マスタ
 *   PRM_Users       利用者マスタ
 *   PRM_UserOrg1    所属（利用者 × 組織区分1）
 *   PRM_Grants      権限（現行値）
 *   PRM_Requests    申請ヘッダ
 *   PRM_RequestItems 申請明細
 *
 * 列の内部名は英語で作られる（表示名は日本語）。
 * Power Fx はこの内部名を参照するので変えないこと。
 */

const SITE_URL = "https://YOUR-TENANT.sharepoint.com/sites/YOUR-SITE";
const SEED = true; // サンプルデータを投入するか

(async () => {
  const web = SITE_URL.replace(/\/+$/, "");
  const ctx = await (await fetch(web + "/_api/contextinfo", {
    method: "POST", headers: { Accept: "application/json;odata=verbose" },
    credentials: "same-origin",
  })).json();
  const H = {
    Accept: "application/json;odata=verbose",
    "Content-Type": "application/json;odata=verbose",
    "X-RequestDigest": ctx.d.GetContextWebInformation.FormDigestValue,
  };
  const log = (m) => console.log("[PRM] " + m);

  // ---- 1. 衝突確認 ----
  const want = ["PRM_Org1", "PRM_Org2", "PRM_Users", "PRM_UserOrg1",
                "PRM_Grants", "PRM_Requests", "PRM_RequestItems"];
  const existing = (await (await fetch(web + "/_api/web/lists?$select=Title", {
    headers: { Accept: "application/json;odata=nometadata" }, credentials: "same-origin",
  })).json()).value.map((l) => l.Title);
  const clash = want.filter((t) => existing.includes(t));
  if (clash.length) throw new Error("既に同名のリストがあります: " + clash.join(", "));

  // ---- 2. リスト作成 ----
  const desc = {
    PRM_Org1: "権限申請: 組織区分1マスタ",
    PRM_Org2: "権限申請: 組織区分2マスタ",
    PRM_Users: "権限申請: 利用者マスタ",
    PRM_UserOrg1: "権限申請: 所属 (利用者 × 組織区分1)",
    PRM_Grants: "権限申請: 権限 (1行 = 利用者 × 組織区分1 × 権限)",
    PRM_Requests: "権限申請: 申請ヘッダ",
    PRM_RequestItems: "権限申請: 申請明細 (変更前/変更後)",
  };
  for (const t of want) {
    const r = await fetch(web + "/_api/web/lists", {
      method: "POST", headers: H, credentials: "same-origin",
      body: JSON.stringify({
        __metadata: { type: "SP.List" }, Title: t, BaseTemplate: 100,
        Description: desc[t], AllowContentTypes: false, ContentTypesEnabled: false,
      }),
    });
    if (!r.ok) throw new Error(t + " の作成に失敗: " + r.status);
    log(t + " 作成");
  }

  // ---- 3. 列追加 ----
  // Options 25 = AddToDefaultContentType | AddFieldInternalNameHint | AddFieldToDefaultView
  // AddFieldInternalNameHint(8) が無いと内部名が日本語エンコードされる
  const OPT = 25;
  const T = (n, d, len) => `<Field Type="Text" DisplayName="${d}" Name="${n}" StaticName="${n}" MaxLength="${len || 255}" />`;
  const N = (n, d) => `<Field Type="Number" DisplayName="${d}" Name="${n}" StaticName="${n}" Decimals="0" />`;
  const B = (n, d, def) => `<Field Type="Boolean" DisplayName="${d}" Name="${n}" StaticName="${n}"><Default>${def ? 1 : 0}</Default></Field>`;
  const C = (n, d, ch, def) => `<Field Type="Choice" DisplayName="${d}" Name="${n}" StaticName="${n}" Format="Dropdown"><CHOICES>${ch.map((c) => `<CHOICE>${c}</CHOICE>`).join("")}</CHOICES>${def ? `<Default>${def}</Default>` : ""}</Field>`;
  const NO = (n, d) => `<Field Type="Note" DisplayName="${d}" Name="${n}" StaticName="${n}" NumLines="6" RichText="FALSE" AppendOnly="FALSE" />`;
  const DT = (n, d) => `<Field Type="DateTime" DisplayName="${d}" Name="${n}" StaticName="${n}" Format="DateTime" />`;

  const plan = {
    PRM_Org1: [
      T("NameJa", "日本語名称"), T("NameEn", "英語名称"), N("SortOrder", "表示順"),
      B("MsExt", "多段階設定要否(外部接続申請)", false),
      B("MsWlan", "多段階設定要否(無線LAN申請)", false),
      B("MsCloud", "多段階設定要否(クラウド申請)", false),
      B("IsActive", "有効", true),
    ],
    PRM_Org2: [
      T("Org1Code", "親の組織区分1コード", 50),
      T("NameJa", "日本語名称"), T("NameEn", "英語名称"), N("SortOrder", "表示順"),
      B("ApExt", "多段階承認要否(外部接続申請)", false),
      B("ApWlan", "多段階承認要否(無線LAN申請)", false),
      B("ApCloud", "多段階承認要否(クラウド申請)", false),
      B("IsActive", "有効", true),
    ],
    PRM_Users: [
      T("FullName", "氏名"), T("Mail", "メールアドレス"), T("Department", "部署名"),
      T("AdObjectId", "ADオブジェクトID", 100), DT("SyncedAt", "AD最終突合日時"),
      B("IsActive", "有効", true),
    ],
    PRM_UserOrg1: [
      T("GlobalId", "グローバルID", 50), T("Org1Code", "組織区分1コード", 50),
      B("IsActive", "有効", true),
    ],
    PRM_Grants: [
      T("GlobalId", "グローバルID", 50), T("Org1Code", "組織区分1コード", 50),
      C("RoleCode", "権限", ["SECMGR", "CONFORM", "EXTCONN", "WLAN", "CLOUD", "INFOSEC"]),
      C("ScopeType", "範囲", ["ALL", "PICK"], "PICK"),
      NO("Org2Codes", "組織区分2コード (;区切り)"),
      C("CompanyRole", "権限種別", ["PRIMARY", "DEPUTY"]),
      B("IsActive", "有効", true),
      T("LastReqNo", "最終更新申請番号", 50),
    ],
    PRM_Requests: [
      C("ReqType", "申請種別", ["ORG1", "ORG2", "USER", "GRANT"]),
      T("TargetKey", "対象キー", 100), T("TargetName", "対象名称"),
      NO("Summary", "申請内容の要約"),
      T("ApplicantId", "申請者グローバルID", 50), T("ApplicantName", "申請者氏名"),
      DT("SubmittedAt", "申請日時"),
      C("Status", "状態", ["SUBMITTED", "APPLIED", "REJECTED", "CANCELED", "ERROR"], "SUBMITTED"),
      N("ItemCount", "明細件数"),
      T("Org1Code", "組織区分1コード", 50),
    ],
    PRM_RequestItems: [
      T("ReqNo", "申請番号", 50), N("Seq", "連番"),
      C("Operation", "操作", ["ADD", "UPDATE", "DELETE"]),
      C("EntityKind", "対象種別", ["ORG1", "ORG2", "USER", "USERORG1", "GRANT"]),
      T("EntityKey", "対象キー", 200),
      NO("BeforeJson", "変更前"), NO("AfterJson", "変更後"), NO("ChangeText", "変更内容"),
    ],
  };
  const titleName = {
    PRM_Org1: "組織区分1コード", PRM_Org2: "組織区分2コード",
    PRM_Users: "グローバルID", PRM_UserOrg1: "キー",
    PRM_Grants: "キー", PRM_Requests: "申請番号", PRM_RequestItems: "明細キー",
  };

  for (const [list, fields] of Object.entries(plan)) {
    const base = web + `/_api/web/lists/getbytitle('${list}')`;
    await fetch(base + "/fields/getByInternalNameOrTitle('Title')", {
      method: "POST", credentials: "same-origin",
      headers: { ...H, "X-HTTP-Method": "MERGE", "IF-MATCH": "*" },
      body: JSON.stringify({ __metadata: { type: "SP.Field" }, Title: titleName[list] }),
    });
    for (const xml of fields) {
      const r = await fetch(base + "/fields/createfieldasxml", {
        method: "POST", headers: H, credentials: "same-origin",
        body: JSON.stringify({
          parameters: { __metadata: { type: "SP.XmlSchemaFieldCreationInformation" }, SchemaXml: xml, Options: OPT },
        }),
      });
      if (!r.ok) throw new Error(list + " の列作成に失敗: " + xml);
    }
    log(list + " 列追加");
  }

  // ---- 4. インデックス / 一意制約 ----
  const merge = (list, internal, body) =>
    fetch(web + `/_api/web/lists/getbytitle('${list}')/fields/getByInternalNameOrTitle('${internal}')`, {
      method: "POST", credentials: "same-origin",
      headers: { ...H, "X-HTTP-Method": "MERGE", "IF-MATCH": "*" },
      body: JSON.stringify({ __metadata: { type: "SP.Field" }, ...body }),
    });
  // Title は 一意 + 索引（EnforceUniqueValues は Indexed の後）
  for (const l of want) {
    await merge(l, "Title", { Indexed: true });
    await merge(l, "Title", { EnforceUniqueValues: true });
  }
  // 検索・絞り込みに使う列の索引
  const idx = {
    PRM_Org2: ["Org1Code"],
    PRM_Users: ["Mail", "AdObjectId"],
    PRM_UserOrg1: ["GlobalId", "Org1Code"],
    PRM_Grants: ["GlobalId", "Org1Code", "LastReqNo"],
    PRM_Requests: ["TargetKey", "SubmittedAt", "Org1Code"],
    PRM_RequestItems: ["ReqNo", "EntityKey"],
  };
  for (const [l, cols] of Object.entries(idx))
    for (const c of cols) await merge(l, c, { Indexed: true });
  log("索引と一意制約を設定");

  if (!SEED) { log("完了（サンプルデータなし）"); return; }

  // ---- 5. サンプルデータ ----
  const etype = async (list) =>
    (await (await fetch(web + `/_api/web/lists/getbytitle('${list}')?$select=ListItemEntityTypeFullName`, {
      headers: { Accept: "application/json;odata=nometadata" }, credentials: "same-origin",
    })).json()).ListItemEntityTypeFullName;

  const addAll = async (list, items) => {
    const type = await etype(list);
    for (const item of items) {
      const r = await fetch(web + `/_api/web/lists/getbytitle('${list}')/items`, {
        method: "POST", headers: H, credentials: "same-origin",
        body: JSON.stringify({ __metadata: { type }, ...item }),
      });
      if (!r.ok) throw new Error(list + " への投入に失敗: " + JSON.stringify(item));
    }
    log(`${list} サンプル ${items.length} 件`);
  };

  await addAll("PRM_Org1", [
    { Title: "B01", NameJa: "東日本ブロック", NameEn: "East Japan Block", SortOrder: 1,
      MsExt: true, MsWlan: true, MsCloud: true, IsActive: true },
    { Title: "B02", NameJa: "中部ブロック", NameEn: "Central Japan Block", SortOrder: 2,
      MsExt: true, MsWlan: false, MsCloud: true, IsActive: true },
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
  await addAll("PRM_Org2", o2.map(([c, p, ja, en, s, e, w, cl]) => ({
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
  await addAll("PRM_Users", users.map(([g, n, d], i) => ({
    Title: g, FullName: n, Mail: romaji[i] + "@example.com", Department: d, IsActive: true,
  })));

  const memb = users.map(([g]) => [g, "B01"]).concat([["1234567", "B02"], ["2345678", "B02"]]);
  await addAll("PRM_UserOrg1", memb.map(([g, o]) => ({
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
  await addAll("PRM_Grants", grants.map(([g, o, r, s, codes, cr]) => {
    const it = { Title: `${g}#${o}#${r}`, GlobalId: g, Org1Code: o, IsActive: true,
      RoleCode: r, ScopeType: s, Org2Codes: codes };
    if (cr) it.CompanyRole = cr;
    return it;
  }));

  log("完了。Power Apps 側は docs/screens.md を参照。");
})().catch((e) => console.error("[PRM] 失敗:", e));
