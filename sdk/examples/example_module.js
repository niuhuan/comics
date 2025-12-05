/**
 * 示例漫画模块
 * 
 * 这个文件展示了如何创建一个符合标准接口的漫画源模块
 * 所有模块必须导出以下内容:
 * - moduleInfo: 模块信息对象
 * - getCategories(): 获取分类列表
 * - getComics(categoryId, sortBy, page): 获取漫画列表
 * - getComicDetail(comicId): 获取漫画详情
 * - getEps(comicId, page): 获取章节列表
 * - getPictures(comicId, epId, page): 获取图片列表
 * - search(keyword, sortBy, page): 搜索漫画
 */

// ==================== 模块信息 ====================

/**
 * 模块信息
 * @type {ModuleInfo}
 */
const moduleInfo = {
    id: "example",
    name: "示例源",
    version: "1.0.0",
    author: "Developer",
    icon: null,
    description: "这是一个示例漫画源模块，展示了标准接口的实现方式",
    enabled: true,
};

// ==================== 分类接口 ====================

/**
 * 获取分类列表
 * @returns {Promise<Category[]>} 分类列表
 * 
 * Category 结构:
 * {
 *   id: string,          // 分类ID，用于 getComics
 *   title: string,       // 分类标题
 *   description: string | null,  // 分类描述
 *   thumb: RemoteImageInfo | null, // 缩略图
 *   is_web: boolean,     // 是否为网页链接
 *   active: boolean,     // 是否可用
 *   link: string | null, // 网页链接 (当 is_web 为 true 时)
 * }
 */
async function getCategories() {
    // 示例: 返回静态分类列表
    return [
        {
            id: "popular",
            title: "热门",
            description: "热门漫画",
            thumb: null,
            is_web: false,
            active: true,
            link: null,
        },
        {
            id: "latest",
            title: "最新",
            description: "最新更新",
            thumb: {
                original_name: "latest.jpg",
                path: "/images/categories/latest.jpg",
                file_server: "https://example.com",
            },
            is_web: false,
            active: true,
            link: null,
        },
        {
            id: "completed",
            title: "完结",
            description: "已完结漫画",
            thumb: null,
            is_web: false,
            active: true,
            link: null,
        },
    ];
}

// ==================== 漫画列表接口 ====================

/**
 * 获取漫画列表
 * @param {string} categoryId - 分类ID
 * @param {string | null} sortBy - 排序方式 (可选)
 * @param {number} page - 页码 (从1开始)
 * @returns {Promise<ComicsPage>} 漫画分页数据
 * 
 * ComicsPage 结构:
 * {
 *   page_info: PageInfo,     // 分页信息
 *   sort_options: SortOption[], // 可用排序选项
 *   comics: ComicSimple[],   // 漫画列表
 * }
 * 
 * PageInfo 结构:
 * {
 *   total: number,   // 总数量
 *   limit: number,   // 每页数量
 *   page: number,    // 当前页码
 *   pages: number,   // 总页数
 * }
 * 
 * SortOption 结构:
 * {
 *   id: string,      // 排序ID
 *   title: string,   // 排序名称
 * }
 * 
 * ComicSimple 结构:
 * {
 *   id: string,              // 漫画ID
 *   title: string,           // 标题
 *   author: string | null,   // 作者
 *   pages_count: number,     // 总页数
 *   eps_count: number,       // 章节数
 *   finished: boolean,       // 是否完结
 *   categories: string[],    // 分类列表
 *   thumb: RemoteImageInfo | null, // 封面
 *   likes_count: number,     // 点赞数
 * }
 */
async function getComics(categoryId, sortBy, page) {
    // 示例: 使用 HTTP 请求获取数据
    const response = await http.get(`https://api.example.com/comics?category=${categoryId}&sort=${sortBy || 'popular'}&page=${page}`);
    const data = JSON.parse(response);
    
    return {
        page_info: {
            total: data.total,
            limit: data.per_page,
            page: page,
            pages: Math.ceil(data.total / data.per_page),
        },
        sort_options: [
            { id: "popular", title: "人气" },
            { id: "latest", title: "最新" },
            { id: "views", title: "观看数" },
        ],
        comics: data.items.map(item => ({
            id: item.id.toString(),
            title: item.title,
            author: item.author || null,
            pages_count: item.pages || 0,
            eps_count: item.chapters || 1,
            finished: item.is_completed || false,
            categories: item.tags || [],
            thumb: item.cover ? {
                original_name: "cover.jpg",
                path: item.cover,
                file_server: "",
            } : null,
            likes_count: item.likes || 0,
        })),
    };
}

// ==================== 漫画详情接口 ====================

/**
 * 获取漫画详情
 * @param {string} comicId - 漫画ID
 * @returns {Promise<ComicInfo>} 漫画详情
 * 
 * ComicInfo 结构 (继承 ComicSimple 并扩展):
 * {
 *   // ... ComicSimple 的所有字段
 *   description: string | null,   // 描述
 *   chinese_team: string | null,  // 汉化组
 *   tags: string[],               // 标签列表
 *   updated_at: string | null,    // 更新时间
 *   created_at: string | null,    // 创建时间
 *   allow_download: boolean,      // 是否允许下载
 *   views_count: number,          // 观看数
 *   is_favourite: boolean,        // 是否收藏
 *   is_liked: boolean,            // 是否点赞
 *   comments_count: number,       // 评论数
 * }
 */
async function getComicDetail(comicId) {
    const response = await http.get(`https://api.example.com/comics/${comicId}`);
    const data = JSON.parse(response);
    
    return {
        id: data.id.toString(),
        title: data.title,
        author: data.author || null,
        pages_count: data.total_pages || 0,
        eps_count: data.chapters?.length || 1,
        finished: data.is_completed || false,
        categories: data.categories || [],
        thumb: data.cover ? {
            original_name: "cover.jpg",
            path: data.cover,
            file_server: "",
        } : null,
        likes_count: data.likes || 0,
        description: data.description || null,
        chinese_team: data.translator || null,
        tags: data.tags || [],
        updated_at: data.updated_at || null,
        created_at: data.created_at || null,
        allow_download: true,
        views_count: data.views || 0,
        is_favourite: false,
        is_liked: false,
        comments_count: data.comments || 0,
    };
}

// ==================== 章节接口 ====================

/**
 * 获取章节列表
 * @param {string} comicId - 漫画ID
 * @param {number} page - 页码 (从1开始)
 * @returns {Promise<EpPage>} 章节分页数据
 * 
 * EpPage 结构:
 * {
 *   page_info: PageInfo,  // 分页信息
 *   eps: Ep[],            // 章节列表
 * }
 * 
 * Ep 结构:
 * {
 *   id: string,              // 章节ID，用于 getPictures
 *   title: string,           // 章节标题
 *   order: number,           // 章节序号
 *   updated_at: string | null, // 更新时间
 * }
 * 
 * 注意: 
 * - 如果源没有章节概念，可以使用 comicId 作为唯一章节的 id
 * - 如果有多级结构 (如卷/话)，使用冒号连接，如 "vol1:ch1"
 */
async function getEps(comicId, page) {
    const response = await http.get(`https://api.example.com/comics/${comicId}/chapters?page=${page}`);
    const data = JSON.parse(response);
    
    return {
        page_info: {
            total: data.total,
            limit: data.per_page,
            page: page,
            pages: Math.ceil(data.total / data.per_page),
        },
        eps: data.chapters.map((ch, index) => ({
            id: ch.id.toString(),
            title: ch.title || `第${ch.order || index + 1}话`,
            order: ch.order || index + 1,
            updated_at: ch.updated_at || null,
        })),
    };
}

// ==================== 图片接口 ====================

/**
 * 获取图片列表
 * @param {string} comicId - 漫画ID
 * @param {string} epId - 章节ID
 * @param {number} page - 页码 (从1开始)
 * @returns {Promise<PicturePage>} 图片分页数据
 * 
 * PicturePage 结构:
 * {
 *   page_info: PageInfo,    // 分页信息
 *   pictures: Picture[],    // 图片列表
 * }
 * 
 * Picture 结构:
 * {
 *   id: string,             // 图片ID
 *   media: RemoteImageInfo, // 图片信息
 * }
 * 
 * RemoteImageInfo 结构:
 * {
 *   original_name: string,  // 原始文件名
 *   path: string,           // 路径
 *   file_server: string,    // 服务器地址
 * }
 * 
 * 完整图片URL = file_server + path
 * 如果 file_server 为空，则 path 应为完整URL
 */
async function getPictures(comicId, epId, page) {
    const response = await http.get(`https://api.example.com/comics/${comicId}/chapters/${epId}/images?page=${page}`);
    const data = JSON.parse(response);
    
    return {
        page_info: {
            total: data.total,
            limit: data.per_page,
            page: page,
            pages: Math.ceil(data.total / data.per_page),
        },
        pictures: data.images.map((img, index) => ({
            id: `${epId}_${index}`,
            media: {
                original_name: img.filename || `${index + 1}.jpg`,
                path: img.url,
                file_server: "",  // 如果 path 已经是完整URL，则 file_server 为空
            },
        })),
    };
}

// ==================== 搜索接口 ====================

/**
 * 搜索漫画
 * @param {string} keyword - 搜索关键词
 * @param {string | null} sortBy - 排序方式 (可选)
 * @param {number} page - 页码 (从1开始)
 * @returns {Promise<ComicsPage>} 搜索结果分页数据
 */
async function search(keyword, sortBy, page) {
    const encodedKeyword = encodeURIComponent(keyword);
    const response = await http.get(`https://api.example.com/search?q=${encodedKeyword}&sort=${sortBy || 'relevance'}&page=${page}`);
    const data = JSON.parse(response);
    
    return {
        page_info: {
            total: data.total,
            limit: data.per_page,
            page: page,
            pages: Math.ceil(data.total / data.per_page),
        },
        sort_options: [
            { id: "relevance", title: "相关度" },
            { id: "popular", title: "人气" },
            { id: "latest", title: "最新" },
        ],
        comics: data.items.map(item => ({
            id: item.id.toString(),
            title: item.title,
            author: item.author || null,
            pages_count: item.pages || 0,
            eps_count: item.chapters || 1,
            finished: item.is_completed || false,
            categories: item.tags || [],
            thumb: item.cover ? {
                original_name: "cover.jpg",
                path: item.cover,
                file_server: "",
            } : null,
            likes_count: item.likes || 0,
        })),
    };
}

// ==================== 工具函数示例 ====================

/**
 * 全局可用的工具:
 * 
 * 1. HTTP 请求:
 *    - http.get(url, headers?) - GET 请求
 *    - http.post(url, body, headers?) - POST 请求
 *    - http.put(url, body, headers?) - PUT 请求
 *    - http.delete(url, headers?) - DELETE 请求
 * 
 * 2. 加密工具:
 *    - crypto.md5(data) - MD5 哈希
 *    - crypto.sha256(data) - SHA256 哈希
 *    - crypto.hmacSha256(key, data) - HMAC-SHA256
 *    - crypto.aesEncrypt(data, key, iv?, mode?) - AES 加密
 *    - crypto.aesDecrypt(data, key, iv?, mode?) - AES 解密
 *    - crypto.base64Encode(data) - Base64 编码
 *    - crypto.base64Decode(data) - Base64 解码
 * 
 * 3. 存储:
 *    - storage.get(key) - 获取存储的值
 *    - storage.set(key, value) - 存储值
 *    - storage.remove(key) - 删除存储的值
 * 
 * 4. 控制台:
 *    - console.log(...args) - 打印日志
 *    - console.error(...args) - 打印错误
 */

// 示例: 使用存储保存登录状态
async function login(username, password) {
    const response = await http.post("https://api.example.com/auth/login", JSON.stringify({
        username,
        password,
    }), {
        "Content-Type": "application/json",
    });
    
    const data = JSON.parse(response);
    
    if (data.token) {
        // 保存 token 到存储
        storage.set("auth_token", data.token);
        return true;
    }
    
    return false;
}

// 示例: 带认证的请求
async function authenticatedRequest(url) {
    const token = storage.get("auth_token");
    
    const headers = {
        "Content-Type": "application/json",
    };
    
    if (token) {
        headers["Authorization"] = `Bearer ${token}`;
    }
    
    return await http.get(url, headers);
}

// 示例: 使用加密
function generateSignature(data, timestamp) {
    const signString = `${data}${timestamp}secretKey`;
    return crypto.hmacSha256("secretKey", signString);
}

// ==================== 导出 ====================

// 必须导出这些内容
module.exports = {
    moduleInfo,
    getCategories,
    getComics,
    getComicDetail,
    getEps,
    getPictures,
    search,
};
