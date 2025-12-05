/**
 * Comics Browser Module SDK
 * 
 * 本 SDK 提供了开发漫画模块所需的类型定义和工具函数
 */

// ============ 模块元信息 ============

/**
 * 模块元信息
 */
export interface ModuleInfo {
    /** 模块唯一标识符 */
    id: string;
    /** 模块显示名称 */
    name: string;
    /** 模块版本号 (如 "1.0.0") */
    version: string;
    /** 模块描述 */
    description: string;
}

// ============ 分类相关 ============

/**
 * 漫画分类
 */
export interface Category {
    /** 分类ID */
    id: string;
    /** 分类名称 */
    name: string;
    /** 分类封面图URL (可选) */
    cover?: string | null;
}

// ============ 漫画相关 ============

/**
 * 漫画简要信息 (用于列表展示)
 */
export interface ComicSimple {
    /** 漫画ID */
    id: string;
    /** 漫画标题 */
    title: string;
    /** 封面图URL */
    cover: string;
    /** 作者 (可选) */
    author?: string | null;
    /** 更新信息 (如 "更新至第100话") */
    update_info?: string | null;
}

/**
 * 漫画详情
 */
export interface ComicDetail {
    /** 漫画ID */
    id: string;
    /** 漫画标题 */
    title: string;
    /** 封面图URL */
    cover: string;
    /** 作者 (可选) */
    author?: string | null;
    /** 漫画描述/简介 (可选) */
    description?: string | null;
    /** 连载状态 (如 "连载中", "已完结") */
    status?: string | null;
    /** 标签列表 */
    tags: string[];
    /** 章节列表 */
    chapters: Chapter[];
    /** 最后更新时间 (可选) */
    update_time?: string | null;
}

/**
 * 章节信息
 */
export interface Chapter {
    /** 章节ID */
    id: string;
    /** 章节标题 (如 "第1话") */
    title: string;
    /** 更新时间 (可选) */
    update_time?: string | null;
}

// ============ 图片相关 ============

/**
 * 图片信息
 */
export interface ImageInfo {
    /** 图片URL */
    url: string;
    /** 图片宽度 (可选) */
    width?: number | null;
    /** 图片高度 (可选) */
    height?: number | null;
    /** 请求头 (可选, 用于需要特殊请求头的图片) */
    headers?: Record<string, string> | null;
}

/**
 * 章节图片列表
 */
export interface ChapterImages {
    /** 章节ID */
    chapter_id: string;
    /** 图片列表 */
    images: ImageInfo[];
}

// ============ 分页相关 ============

/**
 * 分页信息
 */
export interface PageInfo {
    /** 当前页码 (从1开始) */
    page: number;
    /** 每页数量 */
    page_size: number;
    /** 总数量 (可选) */
    total?: number | null;
    /** 是否还有更多数据 */
    has_more: boolean;
}

/**
 * 漫画列表响应
 */
export interface ComicListResponse {
    /** 漫画列表 */
    comics: ComicSimple[];
    /** 分页信息 */
    page_info: PageInfo;
}

// ============ 搜索相关 ============

/**
 * 搜索参数
 */
export interface SearchParams {
    /** 搜索关键词 */
    keyword: string;
    /** 页码 */
    page: number;
    /** 每页数量 */
    page_size: number;
}

// ============ 获取分类参数 ============

export interface GetCategoriesParams {}

// ============ 获取漫画列表参数 ============

export interface GetComicListParams {
    /** 分类ID */
    categoryId: string;
    /** 页码 */
    page: number;
}

// ============ 获取漫画详情参数 ============

export interface GetComicDetailParams {
    /** 漫画ID */
    comicId: string;
}

// ============ 获取章节图片参数 ============

export interface GetChapterImagesParams {
    /** 漫画ID */
    comicId: string;
    /** 章节ID */
    chapterId: string;
}

// ============ 模块接口 ============

/**
 * 漫画模块接口
 * 
 * 所有模块必须实现此接口的所有方法
 */
export interface IComicModule {
    /** 模块元信息 */
    moduleInfo: ModuleInfo;
    
    /**
     * 获取分类列表
     * @returns 分类数组
     */
    getCategories(): Category[] | Promise<Category[]>;
    
    /**
     * 获取漫画列表
     * @param params 包含分类ID和页码
     * @returns 漫画列表响应
     */
    getComicList(params: GetComicListParams): ComicListResponse | Promise<ComicListResponse>;
    
    /**
     * 获取漫画详情
     * @param params 包含漫画ID
     * @returns 漫画详情
     */
    getComicDetail(params: GetComicDetailParams): ComicDetail | Promise<ComicDetail>;
    
    /**
     * 获取章节图片
     * @param params 包含漫画ID和章节ID
     * @returns 章节图片列表
     */
    getChapterImages(params: GetChapterImagesParams): ChapterImages | Promise<ChapterImages>;
    
    /**
     * 搜索漫画
     * @param params 搜索参数
     * @returns 漫画列表响应
     */
    search(params: SearchParams): ComicListResponse | Promise<ComicListResponse>;
}

// ============ 全局 API (由 App 提供) ============

/**
 * HTTP 请求配置
 */
export interface HttpRequestConfig {
    /** 请求URL */
    url: string;
    /** 请求方法 */
    method?: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';
    /** 请求头 */
    headers?: Record<string, string>;
    /** 请求体 */
    body?: string | null;
    /** 超时时间(秒) */
    timeout_secs?: number;
}

/**
 * HTTP 响应
 */
export interface HttpResponse {
    /** 状态码 */
    status: number;
    /** 响应头 */
    headers: Record<string, string>;
    /** 响应体 */
    body: string;
    /** 内容类型 */
    content_type: string;
}

/**
 * 全局 HTTP 对象
 */
declare global {
    const http: {
        /**
         * GET 请求
         * @param url 请求URL
         * @param headers 请求头
         */
        get(url: string, headers?: Record<string, string>): Promise<HttpResponse>;
        
        /**
         * POST 请求
         * @param url 请求URL
         * @param headers 请求头
         * @param body 请求体
         */
        post(url: string, headers?: Record<string, string>, body?: string | null): Promise<HttpResponse>;
        
        /**
         * 自定义请求
         * @param config 请求配置
         */
        request(config: HttpRequestConfig): Promise<HttpResponse>;
    };
    
    const crypto: {
        /** MD5 哈希 */
        md5(data: string): string;
        /** SHA256 哈希 */
        sha256(data: string): string;
        /** SHA512 哈希 */
        sha512(data: string): string;
        /** Base64 编码 */
        base64Encode(data: string): string;
        /** Base64 解码 */
        base64Decode(data: string): string;
        /** Hex 编码 */
        hexEncode(data: string): string;
        /** Hex 解码 */
        hexDecode(data: string): string;
    };
    
    const storage: {
        /**
         * 获取存储值
         * @param key 键名
         */
        get(key: string): Promise<string | null>;
        
        /**
         * 设置存储值
         * @param key 键名
         * @param value 值
         */
        set(key: string, value: string): Promise<void>;
        
        /**
         * 删除存储值
         * @param key 键名
         */
        remove(key: string): Promise<void>;
        
        /**
         * 列出所有键
         * @param prefix 键前缀
         */
        list(prefix?: string): Promise<string[]>;
    };
    
    const console: {
        log(...args: any[]): void;
        error(...args: any[]): void;
        warn(...args: any[]): void;
        debug(...args: any[]): void;
    };
}

export {};
