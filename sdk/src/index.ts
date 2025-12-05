/**
 * Comics Module SDK - 漫画模块开发套件
 * 参考 pikapika 数据结构设计
 */

// ============ 图片相关 ============

/**
 * 远程图片信息 (参考 pikapika RemoteImageInfo)
 */
export interface RemoteImageInfo {
    originalName: string;
    path: string;
    fileServer: string;
    /** 可选的请求头 */
    headers?: Record<string, string>;
}

/**
 * 创建远程图片信息的辅助函数
 */
export const RemoteImageInfo = {
    /** 从URL创建 */
    fromUrl(url: string, headers?: Record<string, string>): RemoteImageInfo {
        return {
            originalName: '',
            path: url,
            fileServer: '',
            headers: headers || {}
        };
    },
    
    /** 从服务器和路径创建 */
    fromServerPath(fileServer: string, path: string): RemoteImageInfo {
        return {
            originalName: '',
            path,
            fileServer,
            headers: {}
        };
    },
    
    /** 转换为完整URL */
    toUrl(info: RemoteImageInfo): string {
        if (!info.fileServer) {
            return info.path;
        }
        if (info.path.startsWith('http://') || info.path.startsWith('https://')) {
            return info.path;
        }
        return `${info.fileServer}/static/${info.path}`;
    }
};

/**
 * 漫画图片 (参考 pikapika Picture)
 */
export interface Picture {
    id: string;
    media: RemoteImageInfo;
}

// ============ 分页相关 ============

/**
 * 分页信息 (参考 pikapika Page)
 */
export interface PageInfo {
    total: number;
    limit: number;
    page: number;
    pages: number;
}

/**
 * 分页辅助函数
 */
export const PageInfo = {
    /** 创建分页信息 */
    create(page: number, limit: number, total: number): PageInfo {
        const pages = total <= 0 ? 0 : Math.ceil(total / limit);
        return { total, limit, page, pages };
    },
    
    /** 空分页 */
    empty(): PageInfo {
        return { total: 0, limit: 20, page: 1, pages: 0 };
    },
    
    /** 是否有下一页 */
    hasNext(info: PageInfo): boolean {
        return info.page < info.pages;
    }
};

// ============ 分类相关 ============

/**
 * 分类 (参考 pikapika Category)
 */
export interface Category {
    id: string;
    title: string;
    description?: string;
    thumb?: RemoteImageInfo;
    isWeb?: boolean;
    active?: boolean;
    link?: string;
}

// ============ 排序相关 ============

/**
 * 排序选项
 */
export interface SortOption {
    value: string;
    name: string;
}

// ============ 漫画相关 ============

/**
 * 漫画简略信息 (参考 pikapika ComicSimple)
 */
export interface ComicSimple {
    id: string;
    title: string;
    author?: string;
    pagesCount?: number;
    epsCount?: number;
    finished?: boolean;
    categories?: string[];
    thumb: RemoteImageInfo;
    likesCount?: number;
}

/**
 * 漫画详情 (参考 pikapika ComicInfo)
 */
export interface ComicDetail {
    // 基础信息 (来自 ComicSimple)
    id: string;
    title: string;
    author?: string;
    pagesCount?: number;
    epsCount?: number;
    finished?: boolean;
    categories?: string[];
    thumb: RemoteImageInfo;
    likesCount?: number;
    // 详情信息
    description?: string;
    chineseTeam?: string;
    tags?: string[];
    updatedAt?: string;
    createdAt?: string;
    allowDownload?: boolean;
    viewsCount?: number;
    isFavourite?: boolean;
    isLiked?: boolean;
    commentsCount?: number;
}

/**
 * 漫画列表分页 (参考 pikapika ComicsPage)
 */
export interface ComicsPage extends PageInfo {
    docs: ComicSimple[];
}

// ============ 章节相关 ============

/**
 * 章节 (参考 pikapika Ep)
 */
export interface Ep {
    id: string;
    title: string;
    order?: number;
    updatedAt?: string;
}

/**
 * 章节分页 (参考 pikapika EpPage)
 */
export interface EpPage extends PageInfo {
    docs: Ep[];
}

/**
 * 图片分页 (参考 pikapika PicturePage)
 */
export interface PicturePage extends PageInfo {
    docs: Picture[];
}

// ============ 搜索相关 ============

/**
 * 搜索结果
 */
export interface SearchResult extends PageInfo {
    docs: ComicSimple[];
    searchQuery?: string;
}

// ============ 模块接口 ============

/**
 * 模块信息
 */
export interface ModuleInfo {
    id: string;
    name: string;
    version: string;
    author: string;
    description: string;
    icon?: string;
}

/**
 * 获取分类列表参数
 */
export interface GetCategoriesParams {
    // 无参数
}

/**
 * 获取排序选项参数
 */
export interface GetSortOptionsParams {
    // 无参数
}

/**
 * 获取漫画列表参数
 */
export interface GetComicsParams {
    categorySlug: string;
    sortBy: string;
    page: number;
}

/**
 * 获取漫画详情参数
 */
export interface GetComicDetailParams {
    comicId: string;
}

/**
 * 获取章节列表参数
 */
export interface GetEpsParams {
    comicId: string;
    page: number;
}

/**
 * 获取章节图片参数
 */
export interface GetPicturesParams {
    comicId: string;
    epId: string;
    page: number;
}

/**
 * 搜索参数
 */
export interface SearchParams {
    keyword: string;
    sortBy: string;
    page: number;
}

/**
 * 漫画模块接口
 * 所有模块必须实现此接口
 */
export interface IComicModule {
    /** 模块信息 */
    moduleInfo: ModuleInfo;
    
    /** 获取分类列表 */
    getCategories(params: GetCategoriesParams): Promise<Category[]> | Category[];
    
    /** 获取排序选项 */
    getSortOptions(params: GetSortOptionsParams): Promise<SortOption[]> | SortOption[];
    
    /** 获取漫画列表 */
    getComics(params: GetComicsParams): Promise<ComicsPage> | ComicsPage;
    
    /** 获取漫画详情 */
    getComicDetail(params: GetComicDetailParams): Promise<ComicDetail> | ComicDetail;
    
    /** 获取章节列表 */
    getEps(params: GetEpsParams): Promise<EpPage> | EpPage;
    
    /** 获取章节图片 */
    getPictures(params: GetPicturesParams): Promise<PicturePage> | PicturePage;
    
    /** 搜索漫画 */
    search(params: SearchParams): Promise<ComicsPage> | ComicsPage;
}

// ============ 运行时 API ============

/**
 * HTTP 请求选项
 */
export interface HttpRequestOptions {
    method?: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';
    headers?: Record<string, string>;
    body?: string;
    timeout?: number;
}

/**
 * HTTP 响应
 */
export interface HttpResponse {
    status: number;
    headers: Record<string, string>;
    body: string;
}

/**
 * 运行时 API - 由 Rust 提供
 */
export interface RuntimeAPI {
    /** HTTP 请求 */
    http: {
        get(url: string, headers?: Record<string, string>): Promise<HttpResponse>;
        post(url: string, body: string, headers?: Record<string, string>): Promise<HttpResponse>;
        request(url: string, options?: HttpRequestOptions): Promise<HttpResponse>;
    };
    
    /** 加密算法 */
    crypto: {
        md5(input: string): string;
        sha256(input: string): string;
        base64Encode(input: string): string;
        base64Decode(input: string): string;
        hexEncode(input: Uint8Array): string;
        hexDecode(input: string): Uint8Array;
    };
    
    /** 属性存储 */
    storage: {
        get(key: string): Promise<string | null>;
        set(key: string, value: string): Promise<void>;
        remove(key: string): Promise<void>;
        list(prefix?: string): Promise<Array<{key: string, value: string}>>;
    };
    
    /** 控制台日志 */
    console: {
        log(...args: any[]): void;
        info(...args: any[]): void;
        warn(...args: any[]): void;
        error(...args: any[]): void;
    };
}

/**
 * 声明全局 runtime 变量
 */
declare global {
    const runtime: RuntimeAPI;
}

export {};
