# Comics Browser Module SDK

本 SDK 提供了开发 Comics Browser 漫画模块所需的类型定义和工具。

## 安装

```bash
npm install @comics/sdk
# 或
yarn add @comics/sdk
```

## 模块结构

每个模块是一个 `.js` 文件，需要导出以下内容：

### 必须导出

1. **moduleInfo** - 模块元信息
2. **getCategories()** - 获取分类列表
3. **getComicList(params)** - 获取漫画列表
4. **getComicDetail(params)** - 获取漫画详情
5. **getChapterImages(params)** - 获取章节图片
6. **search(params)** - 搜索漫画

## 类型定义

### ModuleInfo (模块元信息)

```typescript
interface ModuleInfo {
    id: string;          // 模块唯一标识符
    name: string;        // 模块显示名称
    version: string;     // 版本号 (如 "1.0.0")
    description: string; // 模块描述
}
```

### Category (分类)

```typescript
interface Category {
    id: string;           // 分类ID
    name: string;         // 分类名称
    cover?: string | null; // 分类封面图URL
}
```

### ComicSimple (漫画简要信息)

```typescript
interface ComicSimple {
    id: string;              // 漫画ID
    title: string;           // 漫画标题
    cover: string;           // 封面图URL
    author?: string | null;  // 作者
    update_info?: string | null; // 更新信息
}
```

### ComicDetail (漫画详情)

```typescript
interface ComicDetail {
    id: string;
    title: string;
    cover: string;
    author?: string | null;
    description?: string | null;
    status?: string | null;    // 连载状态
    tags: string[];
    chapters: Chapter[];
    update_time?: string | null;
}
```

### Chapter (章节)

```typescript
interface Chapter {
    id: string;              // 章节ID
    title: string;           // 章节标题
    update_time?: string | null;
}
```

### ChapterImages (章节图片)

```typescript
interface ChapterImages {
    chapter_id: string;
    images: ImageInfo[];
}

interface ImageInfo {
    url: string;
    width?: number | null;
    height?: number | null;
    headers?: Record<string, string> | null;
}
```

### ComicListResponse (漫画列表响应)

```typescript
interface ComicListResponse {
    comics: ComicSimple[];
    page_info: PageInfo;
}

interface PageInfo {
    page: number;           // 当前页码 (从1开始)
    page_size: number;      // 每页数量
    total?: number | null;  // 总数量
    has_more: boolean;      // 是否还有更多
}
```

## 全局 API

App 会注入以下全局对象供模块使用：

### http - HTTP 请求

```typescript
// GET 请求
const response = await http.get(url, headers);

// POST 请求
const response = await http.post(url, headers, body);

// 自定义请求
const response = await http.request({
    url: 'https://api.example.com/data',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ key: 'value' }),
    timeout_secs: 30
});
```

### crypto - 加密工具

```typescript
crypto.md5('hello');        // MD5 哈希
crypto.sha256('hello');     // SHA256 哈希
crypto.base64Encode('hello'); // Base64 编码
crypto.base64Decode('aGVsbG8='); // Base64 解码
crypto.hexEncode('hello');  // Hex 编码
crypto.hexDecode('68656c6c6f'); // Hex 解码
```

### storage - 存储 (按模块隔离)

```typescript
await storage.set('key', 'value');  // 存储值
const value = await storage.get('key');  // 获取值
await storage.remove('key');  // 删除值
const keys = await storage.list('prefix_');  // 列出键
```

### console - 控制台日志

```typescript
console.log('info message');
console.error('error message');
console.warn('warning message');
console.debug('debug message');
```

## 示例模块

### JavaScript 示例

```javascript
const moduleInfo = {
    id: "my_module",
    name: "我的模块",
    version: "1.0.0",
    description: "这是我的漫画模块"
};

function getCategories() {
    return [
        { id: "hot", name: "热门" },
        { id: "new", name: "最新" }
    ];
}

async function getComicList({ categoryId, page }) {
    const response = await http.get(`https://api.example.com/comics?cat=${categoryId}&page=${page}`);
    const data = JSON.parse(response.body);
    
    return {
        comics: data.list.map(item => ({
            id: item.id,
            title: item.title,
            cover: item.cover,
            author: item.author,
            update_info: item.updateInfo
        })),
        page_info: {
            page: page,
            page_size: 20,
            total: data.total,
            has_more: page * 20 < data.total
        }
    };
}

// ... 其他函数实现

module.exports = {
    moduleInfo,
    getCategories,
    getComicList,
    getComicDetail,
    getChapterImages,
    search
};
```

### TypeScript 示例

参见 `examples/typescript_example.ts`

## 开发流程

1. 使用 TypeScript 编写模块代码
2. 运行 `npm run build` 编译为 JavaScript
3. 将编译后的 `.js` 文件放入 App 的 `modules` 目录
4. 在 App 中扫描并加载模块

## 调试

App 提供了调试功能：

1. 开启调试模式
2. 查看 `console.log` 输出
3. 使用热重载快速测试

## 注意事项

1. 模块 ID 必须唯一且不包含特殊字符
2. 所有异步操作应使用 `async/await`
3. 图片 URL 需要可直接访问，如需特殊请求头请在 `headers` 中指定
4. 存储数据会按 `module_id` 自动隔离
5. 避免在模块中存储敏感信息
